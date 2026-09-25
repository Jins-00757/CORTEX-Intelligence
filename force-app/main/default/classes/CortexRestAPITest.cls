@IsTest
private class CortexRestAPITest {

    private class ApiCall {
        Integer statusCode;
        Map<String, Object> body;
        RestResponse response;
    }

    private static ApiCall call(String method, String uri, String requestBody, Map<String, String> params) {
        // Ingestion publishes CustomerDataEvent__e, whose subscriber re-scores
        // churn at Test.stopTest(); keep every Big Object read in-memory.
        if (CustomerEventSelector.stubbedEvents == null) {
            CortexTestUtils.stubEvents(null);
        }
        RestRequest request = new RestRequest();
        request.httpMethod = method;
        request.requestURI = uri;
        if (requestBody != null) {
            request.requestBody = Blob.valueOf(requestBody);
        }
        if (params != null) {
            request.params.putAll(params);
        }
        RestContext.request = request;
        RestContext.response = new RestResponse();

        if (method == 'POST') {
            CortexRestAPI.doPost();
        } else {
            CortexRestAPI.doGet();
        }

        ApiCall result = new ApiCall();
        result.response = RestContext.response;
        result.statusCode = RestContext.response.statusCode;
        result.body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        return result;
    }

    private static String errorCode(ApiCall result) {
        return (String) ((Map<String, Object>) result.body.get('error')).get('code');
    }

    private static List<Object> results(ApiCall result) {
        return (List<Object>) result.body.get('results');
    }

    private static String statusAt(ApiCall result, Integer index) {
        return (String) ((Map<String, Object>) results(result)[index]).get('status');
    }

    // ------------------------------------------------------------ POST /events

    @IsTest
    static void postSingleEventReturnsCreated() {
        String body = JSON.serialize(new Map<String, Object>{
            'customerId' => 'API-CUST-1',
            'eventType' => 'Purchase',
            'eventTimestamp' => '2026-09-20T10:15:30Z',
            'eventSource' => 'web',
            'amount' => 49.99,
            'payload' => new Map<String, Object>{ 'sku' => 'ABC-1', 'qty' => 2 }
        });

        Test.startTest();
        ApiCall result = call('POST', '/cortex/v1/events', body, null);
        Test.stopTest();

        System.assertEquals(201, result.statusCode);
        System.assertEquals(1, result.body.get('accepted'));
        System.assertEquals(0, result.body.get('rejected'));
        System.assertEquals('created', statusAt(result, 0));
        System.assertEquals('application/json', result.response.headers.get('Content-Type'));
    }

    @IsTest
    static void postMixedBatchReturnsMultiStatusWithPerEventOutcomes() {
        String body = JSON.serialize(new Map<String, Object>{
            'events' => new List<Object>{
                new Map<String, Object>{ 'customerId' => 'API-CUST-1', 'eventType' => 'Login', 'amount' => 10 },
                new Map<String, Object>{ 'eventType' => 'Login' },
                new Map<String, Object>{ 'customerId' => 123, 'eventType' => 'Login' },
                new Map<String, Object>{ 'customerId' => 'API-CUST-1', 'eventType' => 'Login', 'eventTimestamp' => 'yesterday' },
                new Map<String, Object>{ 'customerId' => 'API-CUST-1', 'eventType' => 'Login', 'amount' => 'ten' },
                'not-an-object',
                new Map<String, Object>{ 'customerId' => 'API-CUST-1', 'eventType' => 'Login', 'payload' => 'raw-text' }
            }
        });

        Test.startTest();
        ApiCall result = call('POST', '/cortex/v1/events', body, null);
        Test.stopTest();

        System.assertEquals(207, result.statusCode);
        System.assertEquals(2, result.body.get('accepted'));
        System.assertEquals(5, result.body.get('rejected'));
        System.assertEquals('created', statusAt(result, 0));
        System.assertEquals('rejected', statusAt(result, 1));
        System.assertEquals('rejected', statusAt(result, 2));
        System.assertEquals('rejected', statusAt(result, 3));
        System.assertEquals('rejected', statusAt(result, 4));
        System.assertEquals('rejected', statusAt(result, 5));
        System.assertEquals('created', statusAt(result, 6));
        System.assertEquals('CustomerId is required.', ((Map<String, Object>) results(result)[1]).get('error'));
    }

    @IsTest
    static void postArrayWithOnlyInvalidEventsReturnsBadRequest() {
        Test.startTest();
        ApiCall result = call('POST', '/cortex/v1/events', '[{"eventType":"Login"},{"customerId":"X"}]', null);
        Test.stopTest();

        System.assertEquals(400, result.statusCode);
        System.assertEquals(2, result.body.get('rejected'));
    }

    @IsTest
    static void postDuplicateEventIdsAreReportedAsDuplicates() {
        // evt-existing is already stored; evt-new is sent twice in one request.
        CortexTestUtils.stubEvents(new List<CustomerDataEvents__b>{
            new CustomerDataEvents__b(CustomerId__c = 'API-CUST-1', EventId__c = 'evt-existing', EventTimestamp__c = System.now())
        });
        String body = '[' +
            '{"customerId":"API-CUST-1","eventType":"Login","eventId":"evt-existing"},' +
            '{"customerId":"API-CUST-1","eventType":"Login","eventId":"evt-new"},' +
            '{"customerId":"API-CUST-1","eventType":"Login","eventId":"evt-new"}' +
        ']';

        Test.startTest();
        ApiCall result = call('POST', '/cortex/v1/events', body, null);
        Test.stopTest();

        System.assertEquals(201, result.statusCode);
        System.assertEquals(1, result.body.get('accepted'));
        System.assertEquals(2, result.body.get('duplicates'));
        System.assertEquals('duplicate', statusAt(result, 0));
        System.assertEquals('created', statusAt(result, 1));
        System.assertEquals('duplicate', statusAt(result, 2));
    }

    @IsTest
    static void postOnlyDuplicatesReturnsOk() {
        CortexTestUtils.stubEvents(new List<CustomerDataEvents__b>{
            new CustomerDataEvents__b(CustomerId__c = 'API-CUST-1', EventId__c = 'evt-1', EventTimestamp__c = System.now())
        });

        Test.startTest();
        ApiCall result = call('POST', '/cortex/v1/events', '{"customerId":"API-CUST-1","eventType":"Login","eventId":"evt-1"}', null);
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals(1, result.body.get('duplicates'));
    }

    @IsTest
    static void postRejectsMalformedBodies() {
        Test.startTest();
        ApiCall emptyBody = call('POST', '/cortex/v1/events', '', null);
        ApiCall invalidJson = call('POST', '/cortex/v1/events', '{"customerId":', null);
        ApiCall scalarBody = call('POST', '/cortex/v1/events', '"just a string"', null);
        ApiCall eventsNotArray = call('POST', '/cortex/v1/events', '{"events":"nope"}', null);
        ApiCall emptyArray = call('POST', '/cortex/v1/events', '{"events":[]}', null);
        Test.stopTest();

        System.assertEquals(400, emptyBody.statusCode);
        System.assertEquals('BAD_REQUEST', errorCode(emptyBody));
        System.assertEquals(400, invalidJson.statusCode);
        System.assertEquals('INVALID_JSON', errorCode(invalidJson));
        System.assertEquals(400, scalarBody.statusCode);
        System.assertEquals(400, eventsNotArray.statusCode);
        System.assertEquals(400, emptyArray.statusCode);
    }

    @IsTest
    static void postRejectsOversizedBatch() {
        List<Object> events = new List<Object>();
        for (Integer i = 0; i <= CortexRestAPI.MAX_EVENTS_PER_REQUEST; i++) {
            events.add(new Map<String, Object>{ 'customerId' => 'C', 'eventType' => 'Login' });
        }

        Test.startTest();
        ApiCall result = call('POST', '/cortex/v1/events', JSON.serialize(events), null);
        Test.stopTest();

        System.assertEquals(413, result.statusCode);
        System.assertEquals('PAYLOAD_TOO_LARGE', errorCode(result));
    }

    @IsTest
    static void toEventInputParsesAllSupportedFieldTypes() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"customerId":"  C-1 ","eventType":"Purchase","eventId":"e-1","eventSource":"pos",' +
            '"eventTimestamp":"2026-09-20T10:15:30.000Z","amount":12,"payload":{"a":1}}'
        );

        Test.startTest();
        CustomerEventInput input = CortexRestAPI.toEventInput(raw);
        Test.stopTest();

        System.assertEquals('C-1', input.customerId);
        System.assertEquals('Purchase', input.eventType);
        System.assertEquals('e-1', input.eventId);
        System.assertEquals('pos', input.eventSource);
        System.assertEquals(DateTime.newInstanceGmt(2026, 9, 20, 10, 15, 30), input.eventTimestamp);
        System.assertEquals(12, input.amount);
        System.assertEquals('{"a":1}', input.payload);
    }

    // ------------------------------------------------------------- routing

    @IsTest
    static void unknownRouteReturnsNotFound() {
        Test.startTest();
        ApiCall result = call('GET', '/cortex/v1/unknown', null, null);
        Test.stopTest();

        System.assertEquals(404, result.statusCode);
        System.assertEquals('NOT_FOUND', errorCode(result));
    }

    @IsTest
    static void wrongMethodReturnsMethodNotAllowedWithAllowHeader() {
        Test.startTest();
        ApiCall getEvents = call('GET', '/cortex/v1/events', null, null);
        ApiCall postChurn = call('POST', '/cortex/v1/predictions/churn/C-1', '{}', null);
        Test.stopTest();

        System.assertEquals(405, getEvents.statusCode);
        System.assertEquals('POST', getEvents.response.headers.get('Allow'));
        System.assertEquals(405, postChurn.statusCode);
        System.assertEquals('GET', postChurn.response.headers.get('Allow'));
    }

    @IsTest
    static void pathSegmentsIgnoresQueryStringAndEmptySegments() {
        System.assertEquals(
            new List<String>{ 'segments', 'rfm' },
            CortexRestAPI.pathSegments('/cortex/v1/segments/rfm/?tier=HIGH')
        );
        System.assertEquals(new List<String>(), CortexRestAPI.pathSegments(null));
    }

    // ------------------------------------------ GET /predictions/churn/{id}

    @IsTest
    static void getChurnPredictionReturnsScoreAndUpdatesProfile() {
        CortexTestUtils.insertProfiles(new List<String>{ 'API-CHURN-1' });
        CortexTestUtils.stubEvents(new List<CustomerDataEvents__b>());

        Test.startTest();
        ApiCall result = call('GET', '/cortex/v1/predictions/churn/API-CHURN-1', null, null);
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals('API-CHURN-1', result.body.get('customerId'));
        System.assertEquals(0.85, (Decimal) result.body.get('compositeRisk'));
        System.assertEquals('80-90%', result.body.get('riskBucket'));
        System.assertEquals(true, result.body.get('atRisk'));
        System.assertEquals(5, ((Map<String, Object>) result.body.get('factors')).size());
        System.assertEquals(0.85, CortexTestUtils.profilesByExternalId().get('API-CHURN-1').ChurnRiskScore__c);
    }

    @IsTest
    static void getChurnPredictionForHealthyCustomerIsNotAtRisk() {
        CortexTestUtils.stubEvents(CortexTestUtils.healthyHistory('API-CHURN-OK'));

        Test.startTest();
        ApiCall result = call('GET', '/cortex/v1/predictions/churn/API-CHURN-OK', null, null);
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals(0, (Decimal) result.body.get('compositeRisk'));
        System.assertEquals(false, result.body.get('atRisk'));
    }

    @IsTest
    static void getChurnPredictionDecodesUrlEncodedCustomerId() {
        CortexTestUtils.stubEvents(new List<CustomerDataEvents__b>());

        Test.startTest();
        ApiCall result = call('GET', '/cortex/v1/predictions/churn/ACME%20Corp', null, null);
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals('ACME Corp', result.body.get('customerId'));
    }

    @IsTest
    static void getChurnPredictionRejectsOverlongCustomerId() {
        Test.startTest();
        ApiCall result = call('GET', '/cortex/v1/predictions/churn/' + 'x'.repeat(51), null, null);
        Test.stopTest();

        System.assertEquals(400, result.statusCode);
    }

    @IsTest
    static void getChurnPredictionReturnsServiceUnavailableWhenDisabled() {
        CortexTestUtils.disablePredictions();

        Test.startTest();
        ApiCall result = call('GET', '/cortex/v1/predictions/churn/C-1', null, null);
        Test.stopTest();

        System.assertEquals(503, result.statusCode);
        System.assertEquals('PREDICTIONS_DISABLED', errorCode(result));
    }

    // ------------------------------------------------- GET /segments/rfm

    private static void insertSegmentedProfiles() {
        List<CustomerProfile__c> profiles = CortexTestUtils.insertProfiles(new List<String>{ 'SEG-H1', 'SEG-H2', 'SEG-L1' });
        profiles[0].CustomerSegment__c = 'High';
        profiles[1].CustomerSegment__c = 'High';
        profiles[2].CustomerSegment__c = 'Low';
        update profiles;
    }

    @IsTest
    static void getRfmSegmentReturnsOnlyRequestedTier() {
        // Runs as a real integration user: the response is FLS-filtered, so
        // this also proves Cortex_API_Integration grants the fields it needs.
        User apiUser = CortexTestUtils.createApiUser(true);
        ApiCall result;
        ApiCall limited;

        System.runAs(apiUser) {
            insertSegmentedProfiles();

            Test.startTest();
            result = call('GET', '/cortex/v1/segments/rfm', null, new Map<String, String>{ 'tier' => 'high' });
            limited = call('GET', '/cortex/v1/segments/rfm', null, new Map<String, String>{ 'tier' => 'HIGH', 'limit' => '1' });
            Test.stopTest();
        }

        System.assertEquals(200, result.statusCode);
        System.assertEquals('HIGH', result.body.get('tier'));
        System.assertEquals(2, result.body.get('count'));
        Set<String> externalIds = new Set<String>();
        for (Object member : (List<Object>) result.body.get('customers')) {
            Map<String, Object> fields = (Map<String, Object>) member;
            System.assertEquals('High', fields.get('segment'));
            externalIds.add((String) fields.get('externalCustomerId'));
        }
        System.assertEquals(new Set<String>{ 'SEG-H1', 'SEG-H2' }, externalIds);
        System.assertEquals(1, limited.body.get('count'));
    }

    @IsTest
    static void getRfmSegmentIsForbiddenWithoutApiPermissionSet() {
        User restrictedUser = CortexTestUtils.createApiUser(false);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertSegmentedProfiles(); // separate context avoids MIXED_DML_OPERATION
        }
        ApiCall result;

        System.runAs(restrictedUser) {
            Test.startTest();
            result = call('GET', '/cortex/v1/segments/rfm', null, new Map<String, String>{ 'tier' => 'HIGH' });
            Test.stopTest();
        }

        System.assertEquals(403, result.statusCode);
        System.assertEquals('FORBIDDEN', errorCode(result));
    }

    @IsTest
    static void getRfmSegmentValidatesTierAndLimit() {
        Test.startTest();
        ApiCall missingTier = call('GET', '/cortex/v1/segments/rfm', null, null);
        ApiCall badTier = call('GET', '/cortex/v1/segments/rfm', null, new Map<String, String>{ 'tier' => 'PLATINUM' });
        ApiCall nonNumericLimit = call('GET', '/cortex/v1/segments/rfm', null, new Map<String, String>{ 'tier' => 'LOW', 'limit' => 'abc' });
        ApiCall zeroLimit = call('GET', '/cortex/v1/segments/rfm', null, new Map<String, String>{ 'tier' => 'LOW', 'limit' => '0' });
        ApiCall hugeLimit = call('GET', '/cortex/v1/segments/rfm', null, new Map<String, String>{ 'tier' => 'LOW', 'limit' => '99999999999' });
        Test.stopTest();

        System.assertEquals(400, missingTier.statusCode);
        System.assertEquals(400, badTier.statusCode);
        System.assertEquals(400, nonNumericLimit.statusCode);
        System.assertEquals(400, zeroLimit.statusCode);
        System.assertEquals(400, hugeLimit.statusCode);
    }
}
