# Message Flow Architecture: Redis and RabbitMQ

This document provides a comprehensive analysis of the Redis and RabbitMQ message flow architecture in the CRS (Cybersecurity Reasoning System).

## High-Level Architecture Overview

The CRS uses a hybrid messaging architecture combining **RabbitMQ** for task distribution and inter-service communication, and **Redis** for state management, caching, and coordination.

### Core Components

- **Scheduler**: Central task orchestrator and dispatcher
- **RabbitMQ**: Message broker for task distribution and service communication
- **Redis**: In-memory store for state management, caching, and coordination
- **Worker Services**: Various specialized services consuming tasks

## RabbitMQ Message Flow Architecture

### Exchange Types and Topology

The system uses multiple exchange types defined in [`components/scheduler/internal/messaging/initializer.go`](../components/scheduler/internal/messaging/initializer.go#L8-L26):

```go
// Fanout exchanges
TaskBroadcastExchange   = "task_broadcast_exchange"   // broadcasts tasks to multiple services
CancelBroadcastExchange = "cancel_broadcast_exchange" // broadcasts cancellation signals

// Direct exchange
DirectExchange = "direct_exchange" // routes specific tasks to specific queues
```

### Queue Structure

The messaging system defines specialized queues for different service types:

```go
// Service-specific queues
PrimeFuzzingQueue    = "prime_fuzzing_queue"    // Prime fuzzing tasks
GeneralFuzzingQueue  = "general_fuzzing_queue"  // General fuzzing tasks
DirectedFuzzingQueue = "directed_fuzzing_queue" // Directed fuzzing tasks
SeedgenQueue         = "seedgen_queue"          // Seed generation tasks
CorpusQueue          = "corpus_queue"           // Corpus management tasks
FuncTestQueue        = "func_test_queue"        // Function testing tasks
SarifQueue           = "sarif_queue"            // SARIF processing tasks
TriageQueue          = "triage_queue"           // Bug triage tasks
PatchQueue           = "patch_queue"            // Patch generation tasks
ArtifactQueue        = "artifact_queue"         // Artifact management tasks
```

### Message Flow Patterns

#### 1. Task Broadcasting Pattern

**Source**: [`components/scheduler/service/task_routine.go`](../components/scheduler/service/task_routine.go#L101-L141)

The scheduler broadcasts tasks to multiple services simultaneously using a fanout exchange:

```go
err = ch.Publish(
    messaging.TaskBroadcastExchange, // fanout exchange
    "",                              // routing key ignored for fanout
    false,                           // mandatory
    false,                           // immediate
    amqp.Publishing{
        ContentType: "application/json",
        Body:        buffer.Bytes(),
    },
)
```

**Task Broadcast Group**: Services that receive broadcast tasks:
- PrimeFuzzingQueue
- GeneralFuzzingQueue
- DirectedFuzzingQueue
- SeedgenQueue
- CorpusQueue
- FuncTestQueue
- ArtifactQueue

#### 2. Priority Queue Pattern

**Source**: [`components/triage/task_handler.py`](../components/triage/task_handler.py#L242-L246)

Certain queues support priority messaging for urgent tasks:

```python
channel.queue_declare(
    queue="patch_queue",
    durable=True,
    arguments={"x-max-priority": 10}  # Enable priority support
)
```

**Priority-Enabled Queues**:
- `patch_queue`: Patch generation with priority 1-10
- `triage_queue`: Bug triage with priority support

#### 3. Direct Routing Pattern

Services can send specific messages to targeted queues using direct routing for specialized tasks like timeout handling and deduplication.

### Connection Management

#### Connection Pooling

**Source**: [`components/scheduler/internal/messaging/mq.go`](../components/scheduler/internal/messaging/mq.go#L16-L30)

```go
const ConnectionPoolSize = 10

type rabbitMQImpl struct {
    logger      *zap.Logger
    rabbitmqUrl string
    context     context.Context
    connections []*MQConnection  // Pool of connections
    mu          sync.Mutex
}
```

- **Pool Size**: 10 connections per service
- **Automatic Reconnection**: Built-in connection monitoring and recovery
- **Load Balancing**: Random selection from active connections

#### Health Monitoring

Each connection includes monitoring capabilities:

```go
func (c *MQConnection) monitor(ctx context.Context) {
    c.conn.NotifyClose(c.closeChan)
    // Monitor connection state and mark as closed if needed
}
```

## Redis Architecture and Usage Patterns

### Redis Integration Types

The system uses Redis in multiple configurations:

#### 1. Redis Sentinel (High Availability)

**Source**: [`components/triage/utils/redis.py`](../components/triage/utils/redis.py#L19-L58)

```python
def init_redis(sentinel_hosts_list, master_name_str, password=None, db=0):
    sentinel = Sentinel(sentinel_hosts, socket_timeout=30.0, password=password)
    redis_client = sentinel.master_for(
        master_name,
        socket_timeout=30.0,
        password=password,
        db=db,
        retry=retry,
        retry_on_error=[BusyLoadingError, ConnectionError, TimeoutError]
    )
```

#### 2. Direct Redis Connection (Fallback)

```python
else:
    self.redis_client = redis.Redis(
        host=self.config.redis_host,
        port=self.config.redis_port,
        db=self.config.redis_db,
        decode_responses=True,
    )
```

### Key Data Patterns in Redis

#### 1. Task State Management

**Source**: [`components/scheduler/service/task_routine.go`](../components/scheduler/service/task_routine.go#L246-L262)

```go
GlobalTaskStatusKey = "global:task_status"
TaskTraceCtxKey     = "global:trace_context:%s"

// Set task status
err := r.redisClient.Set(
    context.Background(),
    GlobalTaskStatusKey+":"+taskID, // e.g., global:task_status:<task_id>
    "processing",
    0,
).Err()
```

**Status Values**:
- `processing`: Task is actively being processed
- `waiting`: Task is queued but not yet started
- `canceled`: Task has been canceled

#### 2. Task Data Caching

**Source**: [`components/primefuzz/modules/redis_middleware.py`](../components/primefuzz/modules/redis_middleware.py#L239-L277)

```python
# Store complete task payload
hash_key = f"{self.tasks_key_prefix}{task_id}:payload"
redis_payload = {
    k: json.dumps(v) if isinstance(v, (dict, list)) else str(v)
    for k, v in payload.items()
}
self.redis_client.hmset(hash_key, redis_payload)
self.redis_client.expire(hash_key, self.prime_task_expiration)  # 48 hours
```

#### 3. Build Caching System

**Source**: [`components/triage/task_handler.py`](../components/triage/task_handler.py#L86-L191)

```python
redis_build_lock = f"lock:triage:global:{task.task_id}:{sanitizer}:{repo_state}:build"
build_status_key = f"triage:global:{task.task_id}:{sanitizer}:{repo_state}:build_status"

lock = redis.lock.Lock(get_redis_client(), redis_build_lock, timeout=600)
```

**Build States**:
- `building`: Build is in progress
- `done`: Build completed successfully

#### 4. Metrics and Monitoring

**Source**: [`components/primefuzz/modules/redis_middleware.py`](../components/primefuzz/modules/redis_middleware.py#L398-L425)

```python
def append_task_metrics(self, task_id: str, metrics: dict) -> bool:
    metrics_key = f"{self.task_metrics_key_prefix}{task_id}"
    metrics_json = json.dumps(metrics)
    self.redis_client.rpush(metrics_key, metrics_json)  # Append to list
    self.redis_client.expire(metrics_key, self.task_metrics_expiration)  # 15 min
```

#### 5. Distributed Locking

```python
# Coordinated access to shared resources
redis_new_profile_lock = f"lock:triage:{task.task_id}:new_profile"
new_profile_lock = redis.lock.Lock(get_redis_client(), redis_new_profile_lock, timeout=600)
```

### Data Expiration Policies

Different data types have specific TTL (Time To Live) policies:

```python
self.task_metrics_expiration = 15 * 60      # 15 minutes
self.slice_task_expiration = 24 * 60 * 60   # 24 hours
self.prime_task_expiration = 48 * 60 * 60   # 48 hours
```

## Service-Specific Message Flow Patterns

### 1. Scheduler Service

**Role**: Central task orchestrator and message broker

**Message Flow**:
```
Database Tasks → Scheduler → RabbitMQ Fanout Exchange → Multiple Worker Queues
                     ↓
                Redis (Task Status, Tracing Context)
```

**Key Functions**:
- Fetches pending tasks from database
- Publishes to `task_broadcast_exchange` (fanout)
- Updates Redis with task status and tracing context
- Manages task lifecycle and failure counts

### 2. Triage Service

**Role**: Bug analysis and classification

**Source**: [`components/triage/task_handler.py`](../components/triage/task_handler.py#L574-L598)

**Message Flow**:
```
triage_queue → Process Bug → Redis (Bug Profiles) → Database → patch_queue/timeout_queue
```

**Key Functions**:
- Consumes from `triage_queue`
- Builds projects with different sanitizers
- Performs deduplication using Redis locks
- Sends results to patch queue with priority

### 3. Seedgen Service

**Role**: AI-powered seed generation

**Source**: [`components/seedgen/task_handler.py`](../components/seedgen/task_handler.py#L384-L407)

**Message Flow**:
```
seedgen_queue → Generate Seeds → Database → cmin_queue (for non-Java projects)
```

**Key Functions**:
- Runs multiple AI models in parallel (GPT-4, Claude, etc.)
- Stores generated seeds in database
- Forwards seeds to corpus minimization queue

### 4. PrimeFuzz Service

**Role**: Advanced fuzzing orchestration

**Source**: [`components/primefuzz/modules/message_consumer.py`](../components/primefuzz/modules/message_consumer.py#L14-L33)

**Message Flow**:
```
prime_fuzzing_queue → Process Task → Redis (Task Data, Metrics) → Results
```

**Key Functions**:
- Advanced fuzzing task processing
- Real-time metrics collection in Redis
- Task retry logic with exponential backoff

### 5. Submitter Service

**Role**: Result submission and coordination

**Source**: [`components/submitter/redisio.py`](../components/submitter/redisio.py#L36-L109)

**Message Flow**:
```
Redis Queue → Process Results → External Submission → Status Updates
```

**Key Functions**:
- Processes results from Redis queues
- Handles external API submissions
- Updates submission status

## Message Retry and Error Handling

### Retry Mechanisms

**RabbitMQ Level**:
```python
# Message-level retry with headers
retry_count = properties.headers.get("x-retry", 0)
if retry_count < 3:
    new_retry = retry_count + 1
    new_headers = {"x-retry": new_retry}
    # Republish with updated retry count
```

**Application Level**:
```python
# Redis-based retry tracking
async def increment_workflow_retry_count(self, task_id: str) -> int:
    retry_key = f"workflow_retry_count:{task_id}"
    new_count = self.redis_client.incr(retry_key)
    self.redis_client.expire(retry_key, self.prime_task_expiration)
    return new_count
```

### Error Handling Patterns

1. **Connection Resilience**: Automatic reconnection with exponential backoff
2. **Message Durability**: All queues declared as durable
3. **Transaction Safety**: Database transactions with rollback on errors
4. **Distributed Locking**: Prevents race conditions in critical sections

## Configuration and Deployment

### Environment Variables

**RabbitMQ Configuration**:
```bash
RABBITMQ_HOST=amqp://user:password@host:port/
QUEUE_NAME=service_specific_queue
```

**Redis Configuration**:
```bash
REDIS_SENTINEL_HOSTS=host1:port1,host2:port2,host3:port3
REDIS_MASTER=mymaster
REDIS_PASSWORD=secret
```

### Kubernetes Integration

**Source**: [`deployment/crs-k8s/b3yond-crs/charts/*/templates/deployment.yaml`](../deployment/crs-k8s/b3yond-crs/charts/)

The system is designed for Kubernetes deployment with:
- **Service Mesh**: Each component runs as a separate pod
- **ConfigMaps**: Environment-specific configuration
- **Secrets**: Secure credential management
- **Persistent Volumes**: Shared storage for artifacts

## Performance Characteristics

### Throughput Optimizations

1. **Connection Pooling**: 10 connections per RabbitMQ client
2. **Prefetch Control**: `prefetch_count=1-28` depending on service
3. **Parallel Processing**: ThreadPoolExecutor for concurrent task processing
4. **Redis Pipelining**: Batch operations where possible

### Scalability Features

1. **Horizontal Scaling**: Multiple instances per service type
2. **Queue-based Load Balancing**: Natural distribution via queues
3. **Redis Clustering**: Sentinel-based high availability
4. **Priority Queues**: Critical tasks get precedence

## Security Considerations

### Authentication and Authorization

1. **Redis**: Password-based authentication with Sentinel
2. **RabbitMQ**: User/password authentication via URL parameters
3. **TLS**: Configurable encryption for connections

### Data Security

1. **Message Persistence**: Durable queues prevent message loss
2. **Redis Persistence**: Configurable persistence policies
3. **Access Control**: Service-specific queue access patterns

## Monitoring and Observability

### Telemetry Integration

**Source**: [`components/scheduler/service/task_routine.go`](../components/scheduler/service/task_routine.go#L70-L98)

```go
span := fmt.Sprintf("BugBuster:Processing:%s", task.ID)
tracer := r.tracerFactory.NewTracer(context.Background(), span)
tracer.Start()
defer tracer.End()

// Export tracing context to Redis
tracingPayload := tracer.Export()
r.setRedisTaskTracingContext(task.ID, tracingPayload)
```

### Metrics Collection

1. **Task Metrics**: Real-time progress tracking in Redis
2. **Queue Depth**: Monitoring via RabbitMQ management API
3. **Connection Health**: Built-in connection monitoring
4. **OpenTelemetry**: Distributed tracing across services

## Conclusion

The CRS messaging architecture demonstrates a sophisticated approach to distributed task processing, combining the strengths of RabbitMQ for reliable message delivery with Redis for high-performance state management. The system's design supports:

- **High Availability**: Through connection pooling and sentinel-based failover
- **Scalability**: Via queue-based distribution and horizontal scaling
- **Reliability**: Through message durability and retry mechanisms
- **Performance**: Via parallel processing and intelligent caching
- **Observability**: Through comprehensive metrics and tracing

This hybrid architecture enables the CRS to efficiently coordinate complex cybersecurity workflows across multiple specialized services while maintaining reliability and performance at scale.