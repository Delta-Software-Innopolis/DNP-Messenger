package api

import (
	"log"
	"time"
	"net/http"

	"dnp_messenger/internal/database"
	"dnp_messenger/internal/models"

	"github.com/gin-gonic/gin"
)

type PropagateMessageRequest struct {
    Type      int       `json:"type"`
    Text      string    `json:"text"`
    Sender    string    `json:"sender"`
    Timestamp time.Time `json:"timestamp"`
    RoomID    string    `json:"room_id"`
}

func PropagateMessage(c *gin.Context) {
    var req PropagateMessageRequest
    
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    
    msg := models.Message{
        Type:      req.Type,
        Text:      req.Text,
        Sender:    req.Sender,
        Timestamp: req.Timestamp,
        RoomId:    req.RoomID,
    }
    
    err := database.SaveMessage(&msg)
    if err != nil {
        log.Printf("Error saving propagated message: %v", err)
        c.AbortWithStatus(http.StatusInternalServerError)
        return
    }
    
    wsHub.broadcast(req.RoomID, []models.Message{msg})
    
    c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
