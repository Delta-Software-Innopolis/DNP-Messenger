package api

import (
	"log"
	"net/http"

	"dnp_messenger/internal/database"

	"github.com/gin-gonic/gin"
)


type PropagateLeaveRequest struct {
	RoomID string `json:"room_id"`
	Alias  string `json:"alias"`
}

func PropagateLeave(c *gin.Context) {
	var req PropagateLeaveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	isMember, err := database.IsMemberInRoom(req.RoomID, req.Alias)
	if err != nil {
		log.Printf("Error checking membership in propagate leave: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	if !isMember {
		c.JSON(http.StatusOK, gin.H{"status": "not a member"})
		return
	}

	err = database.RemoveMember(req.RoomID, req.Alias)
	if err != nil {
		log.Printf("Error removing member in propagate leave: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	memberCount, err := database.GetMemberCount(req.RoomID)
	if err != nil {
		log.Printf("Error getting member count in propagate leave: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	if memberCount == 0 {
		err = database.DeleteRoom(req.RoomID)
		if err != nil {
			log.Printf("Error deleting empty room in propagate leave: %v", err)
			c.AbortWithStatus(http.StatusInternalServerError)
			return
		}
		log.Printf("Room %s was deleted because it became empty", req.RoomID)
	}

	log.Printf("Synced user %s leaving room %s to this server", req.Alias, req.RoomID)
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
