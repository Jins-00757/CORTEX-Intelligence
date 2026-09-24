/**
 * Outcome of attempting to ingest a single customer event via DataIngestionService.
 */
public class IngestionResult {
    public Boolean isSuccess;
    public Boolean isDuplicate;
    public String eventId;
    public String errorMessage;

    private IngestionResult() {
    }

    public static IngestionResult success(String eventId) {
        IngestionResult result = new IngestionResult();
        result.isSuccess = true;
        result.isDuplicate = false;
        result.eventId = eventId;
        return result;
    }

    public static IngestionResult duplicateEvent(String eventId) {
        IngestionResult result = new IngestionResult();
        result.isSuccess = false;
        result.isDuplicate = true;
        result.eventId = eventId;
        return result;
    }

    public static IngestionResult failure(String errorMessage) {
        IngestionResult result = new IngestionResult();
        result.isSuccess = false;
        result.isDuplicate = false;
        result.errorMessage = errorMessage;
        return result;
    }
}
