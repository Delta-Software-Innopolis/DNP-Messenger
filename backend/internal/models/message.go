package models

import "time"

const (
	T_TEXT = iota
	T_USER_ENTER
	T_USER_LEAVE
)

type Message struct {
	Id        string    `json:"id"`
	Type      int       `json:"type"`
	Text      string    `json:"text"`
	Sender    string    `json:"sender"`
	Timestamp time.Time `json:"timestamp"`
	RoomId    string    `json:"room_id"`
}
