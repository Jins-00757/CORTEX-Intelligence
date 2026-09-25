/**
 * Public REST surface for Cortex Intelligence (docs/ARCHITECTURE.md, Layer 6).
 * Base path: /services/apexrest/cortex/v1
 *
 *   POST /events                        Ingest one event, a JSON array of
 *                                       events, or {"events": [...]}
 *   GET  /predictions/churn/{customerId} Real-time churn score for a customer
 *   GET  /segments/rfm?tier=HIGH&limit=N Customer profiles in an RFM tier
 *
 * Apex REST allows one handler per HTTP verb per class, so this class is a
 * thin router: it parses/validates the HTTP request, delegates to the service
 * layer, and renders a consistent JSON body. Every error uses the same
 * envelope, {"error": {"code": "...", "message": "..."}}, and unexpected
 * exceptions are logged but never echoed back (no stack traces to callers).
 */
@RestResource(urlMapping='/cortex/v1/*')
global with sharing class CortexRestAPI {

    @TestVisible
    private static final Integer MAX_EVENTS_PER_REQUEST = 200;
    @TestVisible
    private static final Integer DEFAULT_SEGMENT_LIMIT = 200;
    @TestVisible
    private static final Integer MAX_SEGMENT_LIMIT = 2000;

    private static final String BASE_PATH = '/cortex/v1';
    private static final String CONTENT_TYPE_JSON = 'application/json';

    private static final Map<String, String> SEGMENT_BY_TIER = new Map<String, String>{
        'HIGH' => 'High', 'MID' => 'Mid', 'LOW' => 'Low'
    };

    @HttpPost
    global static void doPost() {
        handle('POST');
    }

    @HttpGet
    global static void doGet() {
        handle('GET');
    }

    private static void handle(String method) {
        RestRequest request = RestContext.request;
        try {
            List<String> segments = pathSegments(request.requestURI);
            ApiResponse response = route(method, segments, request);
            respond(response);
        } catch (ApiException e) {
            respond(error(e.statusCode, e.code, e.getMessage()));
        } catch (JSONException e) {
            respond(error(400, 'INVALID_JSON', 'Request body is not valid JSON.'));
        } catch (CortexServiceException e) {
            respond(error(400, 'BAD_REQUEST', e.getMessage()));
        } catch (NoAccessException e) {
            // Raised by Security.stripInaccessible when the caller lacks
            // object-level access (e.g. missing Cortex_API_Integration).
            respond(error(403, 'FORBIDDEN', 'Insufficient access to the requested resource.'));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CortexRestAPI ' + method + ' ' + request.requestURI +
                ' failed: ' + e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
            respond(error(500, 'INTERNAL_ERROR', 'An unexpected error occurred.'));
        }
    }

    private static ApiResponse route(String method, List<String> segments, RestRequest request) {
        String resource = segments.isEmpty() ? '' : segments[0];

        if (resource == 'events' && segments.size() == 1) {
            requireMethod(method, 'POST');
            return handleIngestEvents(request);
        }
        if (resource == 'predictions' && segments.size() == 3 && segments[1] == 'churn') {
            requireMethod(method, 'GET');
            return handleChurnPrediction(decodePathSegment(segments[2]));
        }
        if (resource == 'segments' && segments.size() == 2 && segments[1] == 'rfm') {
            requireMethod(method, 'GET');
            return handleRfmSegment(request.params);
        }
        throw new ApiException(404, 'NOT_FOUND', 'No resource at ' + method + ' ' + BASE_PATH + '/' + String.join(segments, '/'));
    }

    // ---------------------------------------------------------------- POST /events

    private static ApiResponse handleIngestEvents(RestRequest request) {
        String body = request.requestBody == null ? null : request.requestBody.toString();
        if (String.isBlank(body)) {
            throw new ApiException(400, 'BAD_REQUEST', 'Request body is required.');
        }

        List<Object> rawEvents = extractEventList(JSON.deserializeUntyped(body));
        if (rawEvents.isEmpty()) {
            throw new ApiException(400, 'BAD_REQUEST', 'At least one event is required.');
        }
        if (rawEvents.size() > MAX_EVENTS_PER_REQUEST) {
            throw new ApiException(413, 'PAYLOAD_TOO_LARGE',
                'A request may contain at most ' + MAX_EVENTS_PER_REQUEST + ' events; received ' + rawEvents.size() + '.');
        }

        // Parse failures are reported per event (at their original index) so
        // one malformed item never rejects the rest of the batch.
        List<IngestionResult> results = new List<IngestionResult>();
        List<CustomerEventInput> parsedInputs = new List<CustomerEventInput>();
        List<Integer> parsedIndexes = new List<Integer>();
        for (Integer i = 0; i < rawEvents.size(); i++) {
            results.add(null);
            try {
                parsedInputs.add(toEventInput(rawEvents[i]));
                parsedIndexes.add(i);
            } catch (ApiException e) {
                results[i] = IngestionResult.failure(e.getMessage());
            }
        }

        if (!parsedInputs.isEmpty()) {
            List<IngestionResult> ingested = DataIngestionService.ingest(parsedInputs, true);
            for (Integer j = 0; j < ingested.size(); j++) {
                results[parsedIndexes[j]] = ingested[j];
            }
        }

        return buildIngestResponse(results);
    }

    private static List<Object> extractEventList(Object root) {
        if (root instanceof List<Object>) {
            return (List<Object>) root;
        }
        if (root instanceof Map<String, Object>) {
            Map<String, Object> rootMap = (Map<String, Object>) root;
            if (!rootMap.containsKey('events')) {
                return new List<Object>{ rootMap };
            }
            Object events = rootMap.get('events');
            if (events instanceof List<Object>) {
                return (List<Object>) events;
            }
            throw new ApiException(400, 'BAD_REQUEST', '"events" must be a JSON array.');
        }
        throw new ApiException(400, 'BAD_REQUEST', 'Request body must be a JSON object or array.');
    }

    @TestVisible
    private static CustomerEventInput toEventInput(Object rawEvent) {
        if (!(rawEvent instanceof Map<String, Object>)) {
            throw new ApiException(400, 'BAD_REQUEST', 'Each event must be a JSON object.');
        }
        Map<String, Object> fields = (Map<String, Object>) rawEvent;

        CustomerEventInput input = new CustomerEventInput(
            asString(fields.get('customerId'), 'customerId'),
            asString(fields.get('eventType'), 'eventType')
        );
        input.eventId = asString(fields.get('eventId'), 'eventId');
        input.eventSource = asString(fields.get('eventSource'), 'eventSource');
        input.eventTimestamp = asDateTime(fields.get('eventTimestamp'));
        input.amount = asDecimal(fields.get('amount'));

        Object payload = fields.get('payload');
        if (payload != null) {
            input.payload = payload instanceof String ? (String) payload : JSON.serialize(payload);
        }
        return input;
    }

    private static String asString(Object value, String fieldName) {
        if (value == null) {
            return null;
        }
        if (value instanceof String) {
            return ((String) value).trim();
        }
        throw new ApiException(400, 'BAD_REQUEST', fieldName + ' must be a string.');
    }

    private static DateTime asDateTime(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof String) {
            try {
                // JSON's DateTime parser accepts full ISO-8601 (offsets, Z, millis).
                return (DateTime) JSON.deserialize(JSON.serialize(value), DateTime.class);
            } catch (Exception e) {
                // Falls through to the uniform validation error below.
                System.debug(LoggingLevel.FINE, 'Unparseable eventTimestamp: ' + value);
            }
        }
        throw new ApiException(400, 'BAD_REQUEST', 'eventTimestamp must be an ISO-8601 date-time string.');
    }

    private static Decimal asDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        throw new ApiException(400, 'BAD_REQUEST', 'amount must be a number.');
    }

    private static ApiResponse buildIngestResponse(List<IngestionResult> results) {
        IngestSummary summary = new IngestSummary();
        for (Integer i = 0; i < results.size(); i++) {
            IngestionResult result = results[i];
            EventOutcome outcome = new EventOutcome();
            outcome.index = i;
            outcome.eventId = result.eventId;
            if (result.isSuccess) {
                outcome.status = 'created';
                summary.accepted++;
            } else if (result.isDuplicate) {
                outcome.status = 'duplicate';
                summary.duplicates++;
            } else {
                outcome.status = 'rejected';
                outcome.error = result.errorMessage;
                summary.rejected++;
            }
            summary.results.add(outcome);
        }

        Integer statusCode;
        if (summary.rejected == 0) {
            // Duplicates are idempotent replays of already-stored events.
            statusCode = summary.accepted > 0 ? 201 : 200;
        } else {
            statusCode = (summary.accepted + summary.duplicates) > 0 ? 207 : 400;
        }
        return new ApiResponse(statusCode, summary);
    }

    // ------------------------------------------- GET /predictions/churn/{customerId}

    private static ApiResponse handleChurnPrediction(String customerId) {
        if (String.isBlank(customerId)) {
            throw new ApiException(400, 'BAD_REQUEST', 'customerId is required.');
        }
        if (customerId.length() > DataIngestionService.MAX_TEXT_LENGTH) {
            throw new ApiException(400, 'BAD_REQUEST',
                'customerId must be at most ' + DataIngestionService.MAX_TEXT_LENGTH + ' characters.');
        }
        if (!CortexConfigService.isPredictionsEnabled()) {
            throw new ApiException(503, 'PREDICTIONS_DISABLED', 'Churn predictions are currently disabled.');
        }

        ChurnPredictionService.ChurnPredictionResult result = ChurnPredictionService.predict(customerId);
        ChurnPredictionResponse body = new ChurnPredictionResponse();
        body.customerId = result.customerId;
        body.compositeRisk = result.compositeRisk;
        body.riskBucket = result.riskBucket;
        body.recommendation = result.recommendation;
        body.atRisk = result.compositeRisk >= CortexConfigService.getChurnRiskThreshold();
        body.factors = new Map<String, Decimal>{
            'recency' => result.recencyRisk,
            'frequency' => result.frequencyRisk,
            'monetary' => result.monetaryRisk,
            'engagement' => result.engagementRisk,
            'support' => result.supportRisk
        };
        body.generatedAt = System.now();
        return new ApiResponse(200, body);
    }

    // -------------------------------------------------------- GET /segments/rfm

    private static ApiResponse handleRfmSegment(Map<String, String> params) {
        String tier = params.get('tier');
        if (String.isBlank(tier) || !SEGMENT_BY_TIER.containsKey(tier.trim().toUpperCase())) {
            throw new ApiException(400, 'BAD_REQUEST', 'tier is required and must be one of HIGH, MID, LOW.');
        }
        Integer resultLimit = parseLimit(params.get('limit'));
        String segment = SEGMENT_BY_TIER.get(tier.trim().toUpperCase());

        List<CustomerProfile__c> profiles = SegmentBuilderService.querySegment(
            'CustomerSegment__c', '=', segment, resultLimit
        );
        // Enforce the caller's field-level security on the response payload.
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, profiles);

        SegmentResponse body = new SegmentResponse();
        body.tier = segment.toUpperCase();
        for (SObject record : decision.getRecords()) {
            body.customers.add(new SegmentMember(record.getPopulatedFieldsAsMap()));
        }
        body.count = body.customers.size();
        return new ApiResponse(200, body);
    }

    private static Integer parseLimit(String rawLimit) {
        if (String.isBlank(rawLimit)) {
            return DEFAULT_SEGMENT_LIMIT;
        }
        if (!rawLimit.trim().isNumeric()) {
            throw new ApiException(400, 'BAD_REQUEST', 'limit must be a whole number between 1 and ' + MAX_SEGMENT_LIMIT + '.');
        }
        Integer parsed = rawLimit.trim().length() > 9 ? MAX_SEGMENT_LIMIT + 1 : Integer.valueOf(rawLimit.trim());
        if (parsed < 1 || parsed > MAX_SEGMENT_LIMIT) {
            throw new ApiException(400, 'BAD_REQUEST', 'limit must be a whole number between 1 and ' + MAX_SEGMENT_LIMIT + '.');
        }
        return parsed;
    }

    // ------------------------------------------------------------------ plumbing

    @TestVisible
    private static List<String> pathSegments(String requestUri) {
        String path = requestUri == null ? '' : requestUri;
        Integer queryStart = path.indexOf('?');
        if (queryStart >= 0) {
            path = path.substring(0, queryStart);
        }
        if (path.startsWithIgnoreCase(BASE_PATH)) {
            path = path.substring(BASE_PATH.length());
        }
        List<String> segments = new List<String>();
        for (String segment : path.split('/')) {
            if (String.isNotBlank(segment)) {
                segments.add(segment);
            }
        }
        return segments;
    }

    private static String decodePathSegment(String segment) {
        try {
            return EncodingUtil.urlDecode(segment, 'UTF-8');
        } catch (Exception e) {
            // A malformed escape (e.g. a lone '%') is a client error, not a 500.
            throw new ApiException(400, 'BAD_REQUEST', 'customerId is not a valid URL-encoded value.');
        }
    }

    private static void requireMethod(String actual, String allowed) {
        if (actual != allowed) {
            RestContext.response.addHeader('Allow', allowed);
            throw new ApiException(405, 'METHOD_NOT_ALLOWED', actual + ' is not supported on this resource; use ' + allowed + '.');
        }
    }

    private static void respond(ApiResponse response) {
        RestResponse restResponse = RestContext.response;
        restResponse.statusCode = response.statusCode;
        restResponse.addHeader('Content-Type', CONTENT_TYPE_JSON);
        restResponse.responseBody = Blob.valueOf(JSON.serialize(response.body, true));
    }

    @TestVisible
    private class ApiException extends Exception {
        public Integer statusCode;
        public String code;

        public ApiException(Integer statusCode, String code, String message) {
            setMessage(message);
            this.statusCode = statusCode;
            this.code = code;
        }
    }

    private class ApiResponse {
        Integer statusCode;
        Object body;

        ApiResponse(Integer statusCode, Object body) {
            this.statusCode = statusCode;
            this.body = body;
        }
    }

    private static ApiResponse error(Integer statusCode, String code, String message) {
        return new ApiResponse(statusCode, new Map<String, Object>{
            'error' => new Map<String, Object>{ 'code' => code, 'message' => message }
        });
    }

    public class IngestSummary {
        public Integer accepted = 0;
        public Integer duplicates = 0;
        public Integer rejected = 0;
        public List<EventOutcome> results = new List<EventOutcome>();
    }

    public class EventOutcome {
        public Integer index;
        public String status;
        public String eventId;
        public String error;
    }

    public class ChurnPredictionResponse {
        public String customerId;
        public Decimal compositeRisk;
        public String riskBucket;
        public Boolean atRisk;
        public String recommendation;
        public Map<String, Decimal> factors;
        public DateTime generatedAt;
    }

    public class SegmentResponse {
        public String tier;
        public Integer count;
        public List<SegmentMember> customers = new List<SegmentMember>();
    }

    public class SegmentMember {
        public Id id;
        public String name;
        public String externalCustomerId;
        public String customerName;
        public String email;
        public String segment;
        public Decimal churnRiskScore;
        public Decimal lifetimeValue;

        // Reads from the populated-field map rather than the SObject so a
        // field removed by stripInaccessible serialises as absent instead of
        // throwing an "SObject row was retrieved without querying" error.
        SegmentMember(Map<String, Object> fields) {
            this.id = (Id) fields.get('Id');
            this.name = (String) fields.get('Name');
            this.externalCustomerId = (String) fields.get('ExternalCustomerId__c');
            this.customerName = (String) fields.get('CustomerName__c');
            this.email = (String) fields.get('Email__c');
            this.segment = (String) fields.get('CustomerSegment__c');
            this.churnRiskScore = (Decimal) fields.get('ChurnRiskScore__c');
            this.lifetimeValue = (Decimal) fields.get('LifetimeValue__c');
        }
    }
}
