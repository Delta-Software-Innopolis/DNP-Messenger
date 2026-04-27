package api

import (
	"time"
	"net/http"

	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type SyncRequest struct {
	Since string `form:"since" binding:"required"`
}

type SyncResponse struct {
	Rooms    []models.Room    `json:"rooms"`
	Messages []models.Message `json:"messages"`
	Members  []models.Member  `json:"members"`
}

func Sync(c *gin.Context) {
	var req SyncRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	since, err := time.Parse(time.RFC3339, req.Since)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid timestamp"})
		return
	}

	rooms, err := database.GetAllRoomsAfter(since)
	if err != nil {
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	members, err := database.GetAllMembersAfter(since)
	if err != nil {
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	messages, err := database.GetAllMessagesAfter(since)
	if err != nil {
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"rooms":    rooms,
		"members":  members,
		"messages": messages,
	})
}
