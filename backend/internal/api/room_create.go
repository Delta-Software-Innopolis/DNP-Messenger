package api

import (
	"log"
	"net/http"

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

	c.JSON(http.StatusOK, room)
}
