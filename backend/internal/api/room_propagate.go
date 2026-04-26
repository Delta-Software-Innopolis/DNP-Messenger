package api

import (
	"log"
	"net/http"

	"dnp_messenger/internal/database"

	"github.com/gin-gonic/gin"
)

type PropagateRoomRequest struct {
    RoomID string `json:"room_id"`
    Alias  string `json:"alias"`
    Name   string `json:"name"`
}

func PropagateRoom(c *gin.Context) {
	log.Printf("hi")
	var req PropagateRoomRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	
	existingRoom, err := database.GetRoom(req.RoomID)
	if err == nil && existingRoom != nil {
		err = database.AddMember(req.RoomID, req.Alias)
		if err != nil {
			log.Printf("Error adding member to existing room: %v", err)
			c.AbortWithStatus(http.StatusInternalServerError)
			return
		}

		c.JSON(http.StatusOK, existingRoom)
		return
	}
	room, err := database.CreateRoomWithID(req.RoomID, req.Name)
	if err != nil {
		log.Printf("Error creating propagated room: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	err = database.AddMember(room.Id, req.Alias)
	if err != nil {
		log.Printf("Error adding member in propagated room: %v", err)
		c.AbortWithStatus(http.StatusInternalServerError)
		return
	}

	log.Printf("Successfully synced room %s to database on this server", req.RoomID)
	c.JSON(http.StatusOK, room)
}

