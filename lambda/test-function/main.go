package main

import (
	"context"
	"encoding/json"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

type Response struct {
	Message       string `json:"message"`
	Status        string `json:"status"`
	Authorization string `json:"authorization"`
}

func extractAuthorizationHeader(headers map[string]string) string {
	if headers == nil {
		return ""
	}
	if value, ok := headers["Authorization"]; ok {
		return value
	}
	return headers["authorization"]
}

func handler(ctx context.Context, event events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	log.Printf("Received event: %+v", event)

	response := Response{
		Message:       "Hello from test-function!",
		Status:        "success",
		Authorization: extractAuthorizationHeader(event.Headers),
	}

	body, err := json.Marshal(response)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       `{"error": "failed to marshal response"}`,
		}, err
	}

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(body),
	}, nil
}

func main() {
	lambda.Start(handler)
}
