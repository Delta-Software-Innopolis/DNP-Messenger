package models

import "time"

type Member struct {
	RoomID    string    `json:"room_id"`
	Alias     string    `json:"alias"`
	Timestamp time.Time `json:"timestamp"`
}
