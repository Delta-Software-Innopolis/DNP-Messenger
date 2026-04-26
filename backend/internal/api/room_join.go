package api

import (
	"log"
	"net/http"

	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type JoinRoomRequest struct {
	Alias  string `json:"alias" binding:"required"`
	Invite string `json:"invite" binding:"required"`
}

func JoinRoom(c *gin.Context) {
	var req JoinRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	room, err := database.GetRoomByInvite(req.Invite)
	if err != nil {
		log.Printf("Error getting room by invite code: %v", err)
		c.AbortWithStatus(http.StatusNotFound)
		return
	}

	isMember, err := database.IsMemberInRoom(room.Id, req.Alias)

	if err != nil {
		log.Printf("Error checking membership: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	if isMember {
		c.JSON(http.StatusConflict, gin.H{"error": "user already in room"})
		return
	}

	err = database.AddMember(room.Id, req.Alias)
	if err != nil {
		log.Printf("Error adding member: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	room.Members = append(room.Members, req.Alias)
	wsHub.subscribeAliasToRoom(req.Alias, room.Id)

	if err := broadcastRoomEvent(room.Id, req.Alias, models.T_USER_ENTER); err != nil {
		log.Printf("Error broadcasting room join event: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	c.JSON(http.StatusOK, room)
}
