/**
 * Lightweight DTO for an inbound customer event payload, decoupled from the
 * CustomerDataEvents__b Big Object shape so callers (REST API, Platform Event
 * subscribers, batch loaders) don't depend on SObject internals.
 */
public class CustomerEventInput {
    public String customerId;
    public String eventType;
    public DateTime eventTimestamp;
    public String eventSource;
    public Decimal amount;
    public String payload;
    public String eventId;

    public CustomerEventInput(String customerId, String eventType) {
        this.customerId = customerId;
        this.eventType = eventType;
    }
}
