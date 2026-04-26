package utils

import (
	"crypto/sha256"
	"fmt"
	"time"
)

func GenerateInviteCode(name string, roomID int, createdAt time.Time) string {
	input := fmt.Sprintf("%s:%d:%d", name, roomID, createdAt.UnixNano())

	hash := sha256.Sum256([]byte(input))

	const charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	code := ""
	for i := 0; i < 10; i++ {
		code += string(charset[int(hash[i])%len(charset)])
	}

	return code
}