# Gateway Architecture and Service Communication

This document provides a comprehensive analysis of the CRS Gateway implementation, covering both the external API interface and internal service communication patterns.

## High-Level Gateway Architecture

The CRS (Cybersecurity Reasoning System) implements a **dual-gateway architecture**:

1. **External API Gateway** ([`components/gateway`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/)): Handles external client requests and AIxCC competition API compliance
2. **Internal Service APIs**: Scheduler exposes internal REST APIs for inter-service communication

## External API Gateway

### Overview

The external gateway implements the **AIxCC competition API specification** and serves as the primary entry point for external clients, functioning as a single interface for receiving tasks and managing the CRS system's external communication.

### Purpose and Functionality

- **API Gateway Pattern**: Single entry point for all external CRS communications
- **OpenAPI Compliance**: Implements competition-specified API exactly
- **Authentication & Authorization**: Handles Basic Auth for API access
- **Request Processing**: Validates, processes, and routes incoming requests

### Core Technologies

- **Go with OpenAPI Code Generation**: Automatic handler generation from swagger spec
- **GORM**: ORM for database operations
- **Uber FX**: Dependency injection framework
- **Zap**: Structured logging

### Gateway Components

#### 1. Main Entry Point

**Source**: [`components/gateway/cmd/crs-gateway/main.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/cmd/crs-gateway/main.go#L34-L51)

```go
app := fx.New(
    fx.Provide(
        config.NewConfig,
        logger.NewLogger,
        server.NewServer,
        server.NewAuthenticator,
        db.NewDBConnection,
    ),
    fx.Invoke(
        serverLifecycle,
    ),
    handlers.Module,
    middle.Module,
    services.Module,
)
```

#### 2. API Server Configuration

**Source**: [`components/gateway/internal/server/server.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/server/server.go#L44-L87)

```go
func setupHandlers(api *operations.CrsGatewayAPI, p ServerParams) {
    // API /status
    api.StatusGetStatusHandler = p.GetStatusHandler
    api.StatusDeleteStatusHandler = p.DeleteStatusHandler

    // API /task
    api.TaskPostV1TaskHandler = p.PostV1TskHandler
    api.TaskDeleteV1TaskHandler = p.DeleteV1TaskHandler
    api.TaskDeleteV1TaskTaskIDHandler = p.DeleteV1TaskTaskIDHandler

    // API /sarif
    api.SarifPostV1SarifHandler = p.PostV1SarifHandler
}
```

#### 3. Task Handling

**Source**: [`components/gateway/internal/handlers/task_handler.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/handlers/task_handler.go#L32-L47)

```go
func (h *PostV1TskHandler) Handle(params task.PostV1TaskParams, principal any) middleware.Responder {
    userID := principal.(int)

    logger := h.logger.With(zap.Any("params", params), zap.Int("user_id", userID))
    logger.Info("Creating task")

    messageID := params.HTTPRequest.Context().Value(middle.MessageIdKey{}).(string)
    err := h.taskService.CreateTask(params.Payload, messageID, userID)
    if err != nil {
        logger.Error("Failed to create task", zap.Error(err))
        return RespondError(err)
    }

    logger.Info("Task created successfully")
    return task.NewPostV1TaskAccepted()
}
```

### Service Layer Architecture

#### 1. Task Service

**Source**: [`components/gateway/internal/services/task_service.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/services/task_service.go#L21-L26)

```go
type TaskService interface {
    CreateTask(task *models.TypesTask, messageID string, userID int) error
    CancelTask(taskID string) error
    CancelAllTasks() error
}
```

**Task Creation Flow**:
```
External Request → Task Handler → Task Service → Database → Task Records
```

**Key Functions**:
- Validates task types (`full`, `delta`)
- Processes source types (`repo`, `fuzz-tooling`, `diff`)
- Creates database records for tasks and sources
- Stores metadata as JSON

#### 2. Status Service

**Source**: [`components/gateway/internal/services/status_service.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/services/status_service.go#L36-L55)

```go
func (s *StatusServiceImpl) GetTaskStatus() (map[db.TaskStatusEnum]int64, error) {
    var results []StatusCount

    if err := s.db.Model(&db.Task{}).
        Select("status, COUNT(*) as count").
        Where("created_at > ?", s.lastClearTime).
        Group("status").
        Find(&results).Error; err != nil {
        return nil, err
    }

    // Convert to map
    statusCount := make(map[db.TaskStatusEnum]int64)
    for _, result := range results {
        statusCount[result.Status] = int64(result.Count)
    }

    return statusCount, nil
}
```

#### 3. SARIF Service

**Source**: [`components/gateway/internal/services/sarif_service.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/services/sarif_service.go#L27-L35)

```go
func (s *SarifServiceImpl) CreateSarif(sarif *models.TypesSARIFBroadcast, messageID string) error {
    for _, broadcast := range sarif.Broadcasts {
        if err := s.createSingleBroadcast(broadcast, messageID); err != nil {
            return fmt.Errorf("failed to create broadcast: %w", err)
        }
    }

    return nil
}
```

## API Implementation

### OpenAPI Specification

**Source**: [`components/gateway/swagger/crs-swagger-v1.0.yaml`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/swagger/crs-swagger-v1.0.yaml#L219-L315)

The gateway exposes three main API endpoint groups:

#### Status Endpoints
- **GET /status/**: Unauthenticated endpoint reporting CRS status
- **DELETE /status/**: Reset status statistics (authenticated)

#### Task Endpoints
- **POST /v1/task/**: Submit tasks for processing (authenticated)
- **DELETE /v1/task/**: Cancel all tasks (authenticated)
- **DELETE /v1/task/{task_id}**: Cancel specific task (authenticated)

#### SARIF Endpoints
- **POST /v1/sarif/**: Submit SARIF vulnerability reports (authenticated)

### Data Models

#### Task Request Model

**Source**: [`components/gateway/swagger/crs-swagger-v1.0.yaml`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/swagger/crs-swagger-v1.0.yaml#L150-L215)

```yaml
types.TaskDetail:
  properties:
    deadline:
      type: integer
    focus:
      type: string
    harnesses_included:
      type: boolean
    metadata:
      type: object
    project_name:
      type: string
    source:
      items:
        $ref: "#/definitions/types.SourceDetail"
      type: array
    task_id:
      format: uuid
      type: string
    type:
      $ref: "#/definitions/types.TaskType"
```

#### Source Detail Model

```yaml
types.SourceDetail:
  properties:
    sha256:
      description: Integrity hash of the gzipped tarball
      type: string
    type:
      $ref: "#/definitions/types.SourceType"
    url:
      description: URL to fetch the source gzipped tarball
      type: string
```

## Internal Service APIs

### Scheduler Internal API

The scheduler exposes internal REST endpoints for service monitoring and coordination.

**Source**: [`components/scheduler/internal/api/serve.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/scheduler/internal/api/serve.go#L24-L42)

```go
func NewAPIServer(params ServerParams) *http.Server {
    mux := http.NewServeMux()

    // Health endpoint
    mux.HandleFunc("/health", handleHealth(params.HealthService, params.Logger))

    // Status endpoint
    mux.HandleFunc("/status", handleStatus(params.StatusService, params.Logger))

    // Queue endpoint
    mux.HandleFunc("/queue", handleQueue(params.QueueService, params.Logger))

    // Harness endpoint
    mux.HandleFunc("/harness", handleHarness(params.HarnessService, params.Logger))
}
```

#### 1. Health Service

**Functionality**:
- Health check endpoint for Kubernetes readiness/liveness probes
- Competition API connectivity verification
- CRS user creation and validation

#### 2. Queue Service

**Source**: [`components/scheduler/internal/api/queue_service.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/scheduler/internal/api/queue_service.go#L22-L54)

```go
func (q *QueueService) GetQueueLength(queueName string) (int64, error) {
    url := fmt.Sprintf("%s/api/queues/%%2F/%s", q.managementEndpoint, queueName)

    // Call RabbitMQ Management API
    resp, err := http.Get(url)

    // Parse response for queue metrics
    return queueInfo.MessagesUnacked + queueInfo.MessagesReady, nil
}
```

**Queue Monitoring**:
- Connects to **RabbitMQ Management API**
- Returns total message count (unacked + ready)
- Used for system monitoring and load balancing

#### 3. Harness Service

**Source**: [`components/scheduler/internal/api/harness_service.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/scheduler/internal/api/harness_service.go#L35-L61)

```go
func (h *HarnessService) GetHarnessData() (*HarnessResponse, error) {
    tasks, err := h.taskRepo.GetProcessingTasks()

    for _, task := range tasks {
        artifactHarnessKey := fmt.Sprintf(ArtifactHarnessRedisKey, task.ID)
        harnessNames, err := h.redisClient.SMembers(context.Background(), artifactHarnessKey).Result()
        // Aggregate harness data from Redis
    }
}
```

**Harness Tracking**:
- Queries Redis for harness information per task: `artifacts:<task_id>:harnesses`
- Provides harness count estimates for capacity planning
- Used by external monitoring systems

## Service Communication Patterns

### 1. Gateway → Database Pattern

**Direct Database Access**:
```
Gateway Services → GORM → PostgreSQL Database
```

The gateway directly interacts with the database for:
- Task creation and management
- User authentication
- Status aggregation
- SARIF report storage

### 2. Scheduler → External APIs Pattern

**RabbitMQ Management Integration**:
```
Scheduler API → HTTP Client → RabbitMQ Management API → Queue Metrics
```

**Competition API Integration**:
```
Scheduler Health Service → HTTP Client → AIxCC Competition API → Validation
```

### 3. Cross-Service Redis Communication

**Redis as Service Coordination Layer**:
```
Multiple Services → Redis → Shared State (Task Status, Harness Data, etc.)
```

**Key Redis Patterns**:
- **Task Status**: `global:task_status:<task_id>`
- **Harness Data**: `artifacts:<task_id>:harnesses`
- **Trace Context**: `global:trace_context:<task_id>`

## Request Flow Examples

### 1. Task Submission Flow

```mermaid
sequenceDiagram
    Client->>Gateway: POST /v1/task/
    Gateway->>Auth: Validate credentials
    Auth-->>Gateway: User ID
    Gateway->>TaskService: CreateTask()
    TaskService->>Database: Insert task records
    TaskService->>Database: Insert source records
    Database-->>TaskService: Success
    TaskService-->>Gateway: Task created
    Gateway-->>Client: 202 Accepted
```

### 2. Status Query Flow

```mermaid
sequenceDiagram
    Client->>Gateway: GET /status/
    Gateway->>StatusService: GetTaskStatus()
    StatusService->>Database: Query task counts by status
    Database-->>StatusService: Status counts
    StatusService-->>Gateway: Aggregated status
    Gateway-->>Client: Status response
```

### 3. Internal Queue Monitoring Flow

```mermaid
sequenceDiagram
    Monitor->>Scheduler: GET /queue?queue=triage_queue
    Scheduler->>QueueService: GetQueueLength()
    QueueService->>RabbitMQ: HTTP GET /api/queues/%2F/triage_queue
    RabbitMQ-->>QueueService: Queue metrics JSON
    QueueService-->>Scheduler: Message count
    Scheduler-->>Monitor: Queue length response
```

## Authentication and Security

### Basic Authentication

**Source**: [`components/gateway/internal/server/auth.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/server/auth.go)

```go
func (a *Authenticator) BasicAuth(username, password string) (interface{}, error) {
    // Validate credentials against database
    // Return user principal (user ID)
}
```

### Request Tracking and Middleware

**Source**: [`components/gateway/internal/middle/db_message.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/middle/db_message.go)

```go
func (m *DBLogMiddleware) Middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        messageID := uuid.New().String()
        ctx := context.WithValue(r.Context(), MessageIdKey{}, messageID)
        // Track request with unique message ID
    })
}
```

### Data Security

**Database Security**:
- Parameterized queries (GORM ORM)
- Connection pooling with timeouts
- Encrypted connections (TLS)

**API Security**:
- Input validation via OpenAPI schemas
- Request size limits
- Authentication middleware

## Configuration and Deployment

### Gateway Configuration

**Environment Variables**:
```bash
# Database
DATABASE_URL=postgresql://user:pass@host/db

# Server
PORT=8080
VERSION=1.0

# Authentication
BASIC_AUTH_ENABLED=true
```

### Service Discovery

**Kubernetes Service Mesh**:
- Services discover each other via Kubernetes DNS
- No explicit service registry required
- Configuration via environment variables and ConfigMaps

**Example Service Communication**:
```bash
# Gateway to Database
DATABASE_URL=postgresql://postgres-service:5432/crs

# Scheduler to RabbitMQ Management
RABBITMQ_MANAGEMENT_ENDPOINT=http://rabbitmq-service:15672
```

## Error Handling and Resilience

### Gateway Error Handling

**Source**: [`components/gateway/internal/handlers/error.go`](https://github.com/Team-Atlanta/42-afc-crs/blob/main/components/gateway/internal/handlers/error.go)

```go
func RespondError(err error) middleware.Responder {
    // Map internal errors to HTTP status codes
    // Return structured error responses
}
```

### Service Health Checks

**Scheduler Health Service**:
```go
func (h *HealthService) IsReady() bool {
    // Check database connectivity
    // Verify RabbitMQ connection
    // Validate external API access
}
```

## Integration with CRS Ecosystem

### Database Integration

```mermaid
graph TD
    A[HTTP Request] --> B[Gateway API]
    B --> C[Request Validation]
    C --> D[Authentication]
    D --> E[Task Service]
    E --> F[Database Storage]

    F --> G[tasks table]
    F --> H[sources table]
    F --> I[messages table]

    J[Scheduler] --> G
    K[Other Components] --> G
```

### Downstream Integration

- **Scheduler**: Reads tasks from database for processing
- **Build System**: Uses source information for compilation
- **Analysis Tools**: Process tasks based on type and configuration
- **Monitoring**: Tracks API usage and system health

## Performance Characteristics

### Gateway Performance

**Database Connection Pooling**:
```go
// GORM automatically handles connection pooling
db.SetMaxOpenConns(25)
db.SetMaxIdleConns(5)
db.SetConnMaxLifetime(time.Hour)
```

**Concurrent Request Handling**:
- Go's native HTTP server handles concurrent requests
- Database connections managed by GORM pool
- Stateless request processing

### Scheduler API Performance

**Resource Efficiency**:
- Lightweight HTTP endpoints
- Redis for fast data access
- Minimal processing overhead
- Background health check routines

## Scalability Considerations

### Horizontal Scaling

**Gateway Scaling**:
- Stateless design enables multiple replicas
- Database connection pooling
- Load balancing via Kubernetes services

**Scheduler API Scaling**:
- Multiple scheduler instances
- Shared Redis state
- Queue-based load distribution

### Database Scaling

**PostgreSQL Optimization**:
- Connection pooling
- Read replicas for status queries
- Indexing on frequently queried fields

## Monitoring and Observability

### Request Tracking

**Middleware Integration**:
```go
func (m *DBLogMiddleware) Middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        messageID := uuid.New().String()
        ctx := context.WithValue(r.Context(), MessageIdKey{}, messageID)
        // Track request with unique message ID
    })
}
```

### Metrics Collection

**Gateway Metrics**:
- Request counts by endpoint
- Authentication success/failure rates
- Database query performance
- Error rates by service

**Scheduler Metrics**:
- Queue depths across all queues
- Task processing times
- Harness utilization rates
- Health check status

## Conclusion

The CRS gateway architecture demonstrates a well-structured approach to API management and service communication:

**Key Strengths**:
- **Clear Separation**: External gateway vs internal APIs
- **Standards Compliance**: OpenAPI/Swagger specifications
- **Monitoring Integration**: Comprehensive metrics and health checks
- **Security**: Multi-layered authentication and validation
- **Scalability**: Stateless design with shared state management

**Communication Patterns**:
- **Synchronous**: HTTP REST APIs for request/response
- **Asynchronous**: RabbitMQ for task distribution
- **State Sharing**: Redis for cross-service coordination
- **Database**: Direct GORM access for persistence

This Gateway component provides a robust, secure, and compliant API interface that serves as the primary entry point for the CRS system while maintaining full compatibility with the AIxCC competition requirements and efficient internal service coordination capabilities.