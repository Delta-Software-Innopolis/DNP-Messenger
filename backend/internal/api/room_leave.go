package api

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"

	"dnp_messenger/internal/config"
	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type LeaveRoomRequest struct {
	Alias  string `json:"alias" binding:"required"`
	RoomID string    `json:"room_id" binding:"required"`
}

func LeaveRoom(c *gin.Context) {
	var req LeaveRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	isMember, err := database.IsMemberInRoom(req.RoomID, req.Alias)
	if err != nil {
		log.Printf("Error checking membership: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	if !isMember {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not in room"})
		return
	}

	if err := broadcastRoomEvent(req.RoomID, req.Alias, models.T_USER_LEAVE); err != nil {
		log.Printf("Error broadcasting room leave event: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	err = database.RemoveMember(req.RoomID, req.Alias)
	if err != nil {
		log.Printf("Error removing member: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}
	wsHub.unsubscribeAliasFromRoom(req.Alias, req.RoomID)

	propagateReq := PropagateLeaveRequest{
		RoomID: req.RoomID,
		Alias:  req.Alias,
	}

	jsonData, err := json.Marshal(propagateReq)
	if err != nil {
		log.Printf("Error marshaling leave propagate request: %v", err)
		return
	}

	for _, peer := range config.AppConfig.Servers {
		if peer == config.AppConfig.Self {
			continue
		}

		go func(peer string) {
			resp, err := http.Post(
				peer + "/propagate/leave",
				"application/json",
				bytes.NewBuffer(jsonData),
			)
			if err != nil {
				log.Printf("Failed to propagate leave to peer %s: %v", peer, err)
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				log.Printf("Peer %s returned non-OK status %d for leave propagate", peer, resp.StatusCode)
			}

			log.Printf("Successfully propagated room leave of %s from room %s to peer %s", req.Alias, req.RoomID, peer)
		}(peer)
	}

	memberCount, err := database.GetMemberCount(req.RoomID)
	if err != nil {
		log.Printf("Error getting member count: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	if memberCount == 0 {
		err = database.DeleteRoom(req.RoomID)
		if err != nil {
			log.Printf("Error deleting empty room: %v", err)
			c.AbortWithStatus(http.StatusInternalServerError)
			return
		}
	}

	c.Status(http.StatusOK)
}
