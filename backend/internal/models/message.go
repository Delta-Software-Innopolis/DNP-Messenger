package models

import "time"

const (
	T_TEXT = iota
	T_USER_ENTER
	T_USER_LEAVE
)

type Message struct {
	Id int
	Type int
	Text string
	Sender string
	Timestamp time.Time
	RoomId string
}
