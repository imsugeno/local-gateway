package main

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/stretchr/testify/assert"
)

func Test_正常なリクエストで200とJSONレスポンスを返すこと(t *testing.T) {
	event := events.APIGatewayProxyRequest{
		HTTPMethod: "GET",
		Path:       "/test",
		Headers: map[string]string{
			"Authorization": "Bearer test-token",
		},
	}

	resp, err := handler(context.Background(), event)

	assert.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/json", resp.Headers["Content-Type"])

	// レスポンスボディがJSONとしてパース可能か確認
	var body Response
	err = json.Unmarshal([]byte(resp.Body), &body)
	assert.NoError(t, err)
	assert.Equal(t, "Hello from test-function!", body.Message)
	assert.Equal(t, "success", body.Status)
	assert.Equal(t, "Bearer test-token", body.Authorization)
}

func Test_レスポンスのJSON構造が正しいこと(t *testing.T) {
	event := events.APIGatewayProxyRequest{
		Headers: map[string]string{
			"authorization": "Bearer lowercase-token",
		},
	}

	resp, err := handler(context.Background(), event)

	assert.NoError(t, err)

	// JSONとしてパース
	var body map[string]interface{}
	err = json.Unmarshal([]byte(resp.Body), &body)
	assert.NoError(t, err)

	// 期待するフィールドが存在するか確認
	assert.Contains(t, body, "message")
	assert.Contains(t, body, "status")
	assert.Contains(t, body, "authorization")

	// フィールドの型を確認
	_, messageOK := body["message"].(string)
	_, statusOK := body["status"].(string)
	_, authorizationOK := body["authorization"].(string)
	assert.True(t, messageOK, "message should be a string")
	assert.True(t, statusOK, "status should be a string")
	assert.True(t, authorizationOK, "authorization should be a string")
}
