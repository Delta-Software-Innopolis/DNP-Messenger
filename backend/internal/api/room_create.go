package api

import (
	"bytes"
	"log"
	"net/http"
	"encoding/json"

	"dnp_messenger/internal/config"
	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type CreateRoomRequest struct {
	Alias string `json:"alias" binding:"required"`
	Name  string `json:"name" binding:"required"`
}

func CreateRoom(c *gin.Context) {
	var req CreateRoomRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	room, err := database.CreateRoom(req.Name)

	if err != nil {
		log.Printf("Error creating room: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)

		return
	}

	err = database.AddMember(room.Id, req.Alias)

	if err != nil {
		log.Printf("Error adding member: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)

		return
	}

	room.Members = []string{req.Alias}
	wsHub.subscribeAliasToRoom(req.Alias, room.Id)

	if err := broadcastRoomEvent(room.Id, req.Alias, models.T_USER_ENTER); err != nil {
		log.Printf("Error broadcasting room create event: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	propagateReq := PropagateRoomRequest{
		RoomID: room.Id,
		Alias: req.Alias,
		Name: req.Name,
	}
	propagateReqJson, err := json.Marshal(propagateReq)
	if err != nil {
		log.Printf("Failed to marshal when propagating room %s: %v", room.Id, err)
		return
	}
	
	for _, peer := range config.AppConfig.Servers {
		if peer == config.AppConfig.Self {
			continue
		}

		go func(peer string) {
			log.Printf("Propagating room %s to peer %s", room.Id, peer)

			resp, err := http.Post(
				peer + "/propagate/room",
				"application/json",
				bytes.NewBuffer(propagateReqJson),
			)

			if err != nil {
				log.Printf("Failed to propagate room %s to peer %s: %v", room.Id, peer, err)
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				log.Printf("Peer %s return non-OK status %d for room %s", peer, resp.StatusCode, room.Id)
				return
			}
		}(peer)
	}

	c.JSON(http.StatusOK, room)
}
