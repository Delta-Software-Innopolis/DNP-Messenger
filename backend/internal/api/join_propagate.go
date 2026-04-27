package api

import (
	"log"
	"net/http"

	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type PropagateJoinRequest struct {
	RoomID string `json:"room_id"`
	Alias  string `json:"alias"`
}

func PropagateJoin(c *gin.Context) {
	var req PropagateJoinRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("Error binding json: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	isMember, err := database.IsMemberInRoom(req.RoomID, req.Alias)
	if err != nil {
		log.Printf("Error checking membership in propagate join: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	if isMember {
		log.Printf("Already member")
		c.JSON(http.StatusOK, gin.H{"status": "already member"})
		return
	}

	err = database.AddMember(req.RoomID, req.Alias)
	if err != nil {
		log.Printf("Error adding member in propagate join: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	room, err := database.GetRoom(req.RoomID)
	if err != nil {
		log.Printf("Error getting room when propagating: %v", err)
		c.AbortWithStatus(http.StatusNotFound)
		return
	}

	if err := broadcastRoomEvent(room.Id, req.Alias, models.T_USER_ENTER); err != nil {
		log.Printf("Error broadcasting room join event when propagating: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	log.Printf("Synced user %s joining room %s to this server", req.Alias, req.RoomID)
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
