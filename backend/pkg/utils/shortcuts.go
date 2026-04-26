package utils

import (
	"crypto/sha256"
	"fmt"
)

func GenerateInviteCode(name string, roomID string) string {
	input := fmt.Sprintf("%s:%s", name, roomID)

	hash := sha256.Sum256([]byte(input))

	const charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	code := ""
	for i := 0; i < 10; i++ {
		code += string(charset[int(hash[i])%len(charset)])
	}

	return code
}
