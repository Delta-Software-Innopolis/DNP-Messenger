package api

import (
	"log"
	"time"
	"net/http"

	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type PropagateMessageRequest struct {
	Type      int       `json:"type"`
	Text      string    `json:"text"`
	Sender    string    `json:"sender"`
	Timestamp time.Time `json:"timestamp"`
	RoomId    string    `json:"room_id"`
}

func PropagateMessage(c *gin.Context) {
	var req PropagateMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("Failed binding json when propagating message: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	msg := models.Message{
		Type:      req.Type,
		Text:      req.Text,
		Sender:    req.Sender,
		Timestamp: req.Timestamp,
		RoomId:    req.RoomId,
	}
    
	err := database.SaveMessage(&msg)
	if err != nil {
		log.Printf("Error saving propagated message: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}
	wsHub.broadcast(req.RoomId, []models.Message{msg})
	log.Printf("Propagation of message (id=%d, text=%s) to room %s recieved successfully", msg.Id, msg.Text, msg.RoomId)
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
