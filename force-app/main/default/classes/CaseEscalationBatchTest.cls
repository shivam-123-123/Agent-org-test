@IsTest
private class CaseEscalationBatchTest {

    private static Case newCase(String subject, String priority, String status) {
        return new Case(Subject = subject, Priority = priority, Status = status, Origin = 'Web');
    }

    private static void setAge(List<Case> cases, Integer hours) {
        Datetime created = Datetime.now().addHours(-hours);
        for (Case c : cases) {
            Test.setCreatedDate(c.Id, created);
        }
    }

    private static void runBatch() {
        Test.startTest();
        Database.executeBatch(new CaseEscalationBatch(), 200);
        Test.stopTest();
    }

    private static Map<String, Boolean> escalatedBySubject() {
        Map<String, Boolean> result = new Map<String, Boolean>();
        for (Case c : [SELECT Subject, Is_Escalated__c FROM Case]) {
            result.put(c.Subject, c.Is_Escalated__c);
        }
        return result;
    }

    @IsTest
    static void acceptanceCriteria() {
        Case highOld = newCase('highOld', 'High', 'New');
        Case highYoung = newCase('highYoung', 'High', 'New');
        Case lowOld = newCase('lowOld', 'Low', 'New');
        Case closedOld = newCase('closedOld', 'High', 'Closed');
        insert new List<Case>{ highOld, highYoung, lowOld, closedOld };
        setAge(new List<Case>{ highOld, lowOld, closedOld }, 5);
        setAge(new List<Case>{ highYoung }, 2);

        runBatch();

        Map<String, Boolean> escalated = escalatedBySubject();
        Assert.isTrue(escalated.get('highOld'), 'High, open, 5h old must be escalated');
        Assert.isFalse(escalated.get('highYoung'), 'High, open, 2h old must not be escalated');
        Assert.isFalse(escalated.get('lowOld'), 'Low priority must not be escalated');
        Assert.isFalse(escalated.get('closedOld'), 'Closed Case must not be escalated');
    }

    @IsTest
    static void alreadyEscalatedIsSkipped() {
        Case c = newCase('done', 'High', 'New');
        c.Is_Escalated__c = true;
        insert c;
        setAge(new List<Case>{ c }, 5);

        runBatch();

        AsyncApexJob job = [SELECT TotalJobItems FROM AsyncApexJob WHERE ApexClass.Name = 'CaseEscalationBatch' LIMIT 1];
        Assert.areEqual(0, job.TotalJobItems, 'Already escalated Case must not be picked up');
        Assert.isTrue([SELECT Is_Escalated__c FROM Case WHERE Id = :c.Id].Is_Escalated__c, 'Should stay escalated');
    }

    @IsTest
    static void bulk200() {
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            cases.add(newCase('bulk' + i, 'High', 'Working'));
        }
        insert cases;
        setAge(cases, 6);

        runBatch();

        Assert.areEqual(200, [SELECT COUNT() FROM Case WHERE Is_Escalated__c = true], 'All 200 Cases must be escalated');
    }

    @IsTest
    static void noMatchingCases() {
        runBatch();
        Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Is_Escalated__c = true], 'Nothing to escalate');
    }

    @IsTest
    static void schedulableStartsBatch() {
        Test.startTest();
        Id jobId = System.schedule('CaseEscalationBatchTest', '0 0 * * * ?', new CaseEscalationBatch());
        Test.stopTest();

        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual('0 0 * * * ?', ct.CronExpression, 'Job should be scheduled hourly');
        Assert.areEqual(1, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'CaseEscalationBatch'],
            'Scheduled run should start the batch');
    }
}
