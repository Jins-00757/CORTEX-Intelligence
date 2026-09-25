/**
 * Isolates Big Object "immediate" DML behind a single seam.
 *
 * Confirmed platform limitation on this org: Database.insertImmediate()
 * throws "System.UnexpectedException: Internal Salesforce.com Query Error"
 * whenever it executes inside the Apex test runner (sf apex run test /
 * RunLocalTests) - even for the simplest possible single-record insert with
 * no other DML anywhere in the transaction. The identical call succeeds
 * reliably via anonymous Apex (sf apex run) outside the test runner, and
 * Database.insertAsync() is rejected outright ("Asynchronous DML not
 * allowed on CustomerDataEvents__b"), so insertImmediate is the only
 * available write path for these Big Objects.
 *
 * In test context this method is a no-op that returns a synthetic success
 * result, so callers' surrounding business logic (validation, dedup,
 * calculation, branching) remains fully exercised and covered by tests; the
 * real write path is exercised outside the test runner.
 */
public with sharing class BigObjectWriter {

    public class WriteResult {
        public Boolean isSuccess;
        public String errorMessage;
    }

    // Records "written" while running tests, so callers' tests can assert on
    // exactly what would have been persisted.
    @TestVisible
    private static List<SObject> recordsWrittenInTest = new List<SObject>();

    public static List<WriteResult> insertImmediate(List<SObject> records) {
        if (Test.isRunningTest()) {
            recordsWrittenInTest.addAll(records);
            List<WriteResult> syntheticResults = new List<WriteResult>();
            for (Integer i = 0; i < records.size(); i++) {
                WriteResult synthetic = new WriteResult();
                synthetic.isSuccess = true;
                syntheticResults.add(synthetic);
            }
            return syntheticResults;
        }

        List<Database.SaveResult> saveResults = Database.insertImmediate(records);
        List<WriteResult> results = new List<WriteResult>();
        for (Database.SaveResult saveResult : saveResults) {
            WriteResult result = new WriteResult();
            result.isSuccess = saveResult.isSuccess();
            if (!saveResult.isSuccess()) {
                result.errorMessage = saveResult.getErrors().isEmpty()
                    ? 'Unknown error inserting record.'
                    : saveResult.getErrors()[0].getMessage();
            }
            results.add(result);
        }
        return results;
    }

    public static WriteResult insertImmediate(SObject record) {
        return insertImmediate(new List<SObject>{ record })[0];
    }
}
