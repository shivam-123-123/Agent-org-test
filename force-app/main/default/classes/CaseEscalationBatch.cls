/**
 * Flags open High priority Cases older than 4 hours as escalated (Is_Escalated__c = true).
 * Schedule hourly (Anonymous Apex):
 *   System.schedule('Case Escalation Hourly', '0 0 * * * ?', new CaseEscalationBatch());
 */
// without sharing: a system job must see every Case, not only those shared with the scheduling user.
public without sharing class CaseEscalationBatch implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CaseEscalationBatch(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = Datetime.now().addHours(-4);
        return Database.getQueryLocator([
            SELECT Id
            FROM Case
            WHERE Priority = 'High'
              AND Status != 'Closed'
              AND Is_Escalated__c = false
              AND CreatedDate < :cutoff
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Case> scope) {
        for (Case c : scope) {
            c.Is_Escalated__c = true;
        }
        // Partial success: one bad Case (e.g. a validation rule) must not block the rest.
        for (Database.SaveResult sr : Database.update(scope, false)) {
            if (!sr.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Case escalation failed for ' + sr.getId() + ': ' + sr.getErrors());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}
