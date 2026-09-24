/**
 * Convenience accessor for the CortexConfig__mdt.Default_Config record.
 */
public with sharing class CortexConfigService {

    private static CortexConfig__mdt cachedConfig;

    public static CortexConfig__mdt getConfig() {
        if (cachedConfig == null) {
            cachedConfig = CortexConfig__mdt.getInstance('Default_Config');
            if (cachedConfig == null) {
                throw new CortexServiceException('CortexConfig__mdt.Default_Config is not configured.');
            }
        }
        return cachedConfig;
    }

    public static Decimal getChurnRiskThreshold() {
        return getConfig().ChurnRiskThreshold__c;
    }

    public static Integer getBatchSize() {
        return Integer.valueOf(getConfig().BatchSize__c);
    }

    public static Boolean isPredictionsEnabled() {
        return getConfig().EnablePredictions__c;
    }
}
