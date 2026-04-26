package api

import (
	"log"
	"net/http"

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
