package api

import (
	"log"
	"net/http"
	"sync"
	"time"

	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const (
	wsRequestBefore = iota
	wsRequestAfter
	wsRequestText

	postgresInt4Max = int64(1<<31 - 1)
)

type websocketRequest struct {
	Type   int    `json:"type"`
	Count  int64  `json:"count"`
	Before int64  `json:"before"`
	After  int64  `json:"after"`
	Text   string `json:"text"`
	Alias  string `json:"alias"`
	RoomID int    `json:"room_id"`
}

type websocketMessage struct {
	ID        int       `json:"id"`
	Type      int       `json:"type"`
	Text      string    `json:"text"`
	Sender    string    `json:"sender"`
	Timestamp time.Time `json:"timestamp"`
	RoomID    int       `json:"room_id"`
}

type websocketResponse struct {
	Messages []websocketMessage `json:"messages"`
}

type websocketClient struct {
	hub    *websocketHub
	conn   *websocket.Conn
	send   chan websocketResponse
	alias  string
	rooms  map[int]struct{}
	closed bool
}

type websocketHub struct {
	mu             sync.RWMutex
	clientsByRoom  map[int]map[*websocketClient]struct{}
	clientsByAlias map[string]map[*websocketClient]struct{}
}

var (
	wsHub = newWebsocketHub()

	wsUpgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool {
			return true
		},
	}
)

func newWebsocketHub() *websocketHub {
	return &websocketHub{
		clientsByRoom:  make(map[int]map[*websocketClient]struct{}),
		clientsByAlias: make(map[string]map[*websocketClient]struct{}),
	}
}

func (h *websocketHub) register(client *websocketClient, rooms []models.Room) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.clientsByAlias[client.alias] == nil {
		h.clientsByAlias[client.alias] = make(map[*websocketClient]struct{})
	}
	h.clientsByAlias[client.alias][client] = struct{}{}

	for _, room := range rooms {
		h.subscribeClientLocked(client, room.Id)
	}
}

func (h *websocketHub) unregister(client *websocketClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if client.closed {
		return
	}
	client.closed = true

	for roomID := range client.rooms {
		h.unsubscribeClientLocked(client, roomID)
	}

	if aliasClients := h.clientsByAlias[client.alias]; aliasClients != nil {
		delete(aliasClients, client)
		if len(aliasClients) == 0 {
			delete(h.clientsByAlias, client.alias)
		}
	}

	close(client.send)
}

func (h *websocketHub) broadcast(roomID int, messages []models.Message) {
	if len(messages) == 0 {
		return
	}

	response := websocketResponse{Messages: toWebsocketMessages(messages)}

	h.mu.RLock()
	defer h.mu.RUnlock()

	for client := range h.clientsByRoom[roomID] {
		select {
		case client.send <- response:
		default:
			go h.unregister(client)
		}
	}
}

func (h *websocketHub) subscribeAliasToRoom(alias string, roomID int) {
	h.mu.Lock()
	defer h.mu.Unlock()

	for client := range h.clientsByAlias[alias] {
		h.subscribeClientLocked(client, roomID)
	}
}

func (h *websocketHub) unsubscribeAliasFromRoom(alias string, roomID int) {
	h.mu.Lock()
	defer h.mu.Unlock()

	for client := range h.clientsByAlias[alias] {
		h.unsubscribeClientLocked(client, roomID)
	}
}

func (h *websocketHub) clientInRoom(client *websocketClient, roomID int) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()

	_, ok := client.rooms[roomID]
	return ok
}

func (h *websocketHub) subscribeClientLocked(client *websocketClient, roomID int) {
	if client.rooms == nil {
		client.rooms = make(map[int]struct{})
	}
	if _, ok := client.rooms[roomID]; ok {
		return
	}

	if h.clientsByRoom[roomID] == nil {
		h.clientsByRoom[roomID] = make(map[*websocketClient]struct{})
	}

	client.rooms[roomID] = struct{}{}
	h.clientsByRoom[roomID][client] = struct{}{}
}

func (h *websocketHub) unsubscribeClientLocked(client *websocketClient, roomID int) {
	delete(client.rooms, roomID)

	if roomClients := h.clientsByRoom[roomID]; roomClients != nil {
		delete(roomClients, client)
		if len(roomClients) == 0 {
			delete(h.clientsByRoom, roomID)
		}
	}
}

func (client *websocketClient) readPump() {
	defer func() {
		client.hub.unregister(client)
		client.conn.Close()
	}()

	for {
		var req websocketRequest
		if err := client.conn.ReadJSON(&req); err != nil {
			if !websocket.IsCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("Error reading websocket message: %v", err)
			}
			return
		}

		if req.Alias == "" {
			req.Alias = client.alias
		}

		if req.RoomID == 0 || req.Alias != client.alias {
			client.writeError("room_id is required and alias must match websocket connection")
			continue
		}

		if !client.hub.clientInRoom(client, req.RoomID) {
			client.writeError("user is not subscribed to room")
			continue
		}

		client.handleRequest(req)
	}
}

func (client *websocketClient) writePump() {
	defer client.conn.Close()

	for response := range client.send {
		if err := client.conn.WriteJSON(response); err != nil {
			log.Printf("Error writing websocket message: %v", err)
			return
		}
	}
}

func (client *websocketClient) handleRequest(req websocketRequest) {
	switch req.Type {
	case wsRequestBefore:
		if req.Count <= 0 {
			client.writeError("count must be greater than zero")
			return
		}

		count := clampPostgresInt4(req.Count)
		before := clampPostgresInt4(req.Before)

		messages, err := database.GetMessagesBefore(req.RoomID, count, before)
		if err != nil {
			log.Printf("Error getting messages before %d in room %d: %v", req.Before, req.RoomID, err)
			client.writeError("unable to get messages")
			return
		}

		client.send <- websocketResponse{Messages: toWebsocketMessages(messages)}
	case wsRequestAfter:
		after := clampPostgresInt4(req.After)

		messages, err := database.GetMessagesAfter(req.RoomID, after)
		if err != nil {
			log.Printf("Error getting messages after %d in room %d: %v", req.After, req.RoomID, err)
			client.writeError("unable to get messages")
			return
		}

		client.send <- websocketResponse{Messages: toWebsocketMessages(messages)}
	case wsRequestText:
		msg := models.Message{
			Type:      models.T_TEXT,
			Text:      req.Text,
			Sender:    req.Alias,
			Timestamp: time.Now(),
			RoomId:    req.RoomID,
		}

		if err := database.SaveMessage(&msg); err != nil {
			log.Printf("Error saving websocket message: %v", err)
			client.writeError("unable to save message")
			return
		}

		client.hub.broadcast(req.RoomID, []models.Message{msg})
	default:
		client.writeError("unknown message type")
	}
}

func clampPostgresInt4(value int64) int {
	if value < 0 {
		return 0
	}
	if value > postgresInt4Max {
		return int(postgresInt4Max)
	}

	return int(value)
}

func (client *websocketClient) writeError(message string) {
	log.Printf("Websocket request error: %s", message)
}

func toWebsocketMessages(messages []models.Message) []websocketMessage {
	responseMessages := make([]websocketMessage, 0, len(messages))
	for _, msg := range messages {
		responseMessages = append(responseMessages, websocketMessage{
			ID:        msg.Id,
			Type:      msg.Type,
			Text:      msg.Text,
			Sender:    msg.Sender,
			Timestamp: msg.Timestamp,
			RoomID:    msg.RoomId,
		})
	}

	return responseMessages
}

func broadcastRoomEvent(roomID int, alias string, messageType int) error {
	msg := models.Message{
		Type:      messageType,
		Sender:    alias,
		Timestamp: time.Now(),
		RoomId:    roomID,
	}

	if err := database.SaveMessage(&msg); err != nil {
		return err
	}

	wsHub.broadcast(roomID, []models.Message{msg})

	return nil
}

func Websocket(c *gin.Context) {
	var req struct {
		Alias string `form:"alias" binding:"required"`
	}

	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	rooms, err := database.GetRoomsOf(req.Alias)
	if err != nil {
		log.Printf("Error getting websocket rooms: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	conn, err := wsUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("Error upgrading websocket connection: %v", err)
		return
	}

	client := &websocketClient{
		hub:   wsHub,
		conn:  conn,
		send:  make(chan websocketResponse, 256),
		alias: req.Alias,
		rooms: make(map[int]struct{}),
	}

	wsHub.register(client, rooms)

	go client.writePump()
	client.readPump()
}
