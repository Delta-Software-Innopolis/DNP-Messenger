package api

import (
	"log"
	"net/http"

	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type GetRoomsRequest struct {
	Alias string `json:"alias" binding:"required"`
}

type GetRoomsResponse struct {
	Rooms []models.Room `json:"rooms"`
}

func GetRooms(c *gin.Context) {
	var req GetRoomsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	rooms, err := database.GetRoomsOf(req.Alias)
	if err != nil {
		log.Printf("Error getting rooms for alias %s: %v", req.Alias, err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	
	c.JSON(http.StatusOK, GetRoomsResponse{Rooms: rooms})
}
