/*
 * Copyright (c) 2022, Aquiva Labs LLC. All rights reserved.
 * 
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 * 
 * - Redistributions of source code must retain the above copyright notice, 
 *     this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *     this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * - Neither the name of the Aquiva Labs LLC nor the names of its contributors
 *     may be used to endorse or promote products derived from this software without
 *     specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

//Unit tests for AqResult.cls
@isTest
private with sharing class AqTest_AqResult {

    private static final String TEST_TYPE = 'TestResultType';
    private static final String TEST_MESSAGE = 'Test message.';
    private static final String TEST_CODE = 'TestCode';
    private static final String TEST_SCOPE_TYPE = 'TestScopeType';
    private static final String TEST_SCOPE = 'Test.Scope';

    @TestSetup
    private static void setup() {
        AqTest.setup();
    }

    //hasError(), severityAtLeast()
    @isTest
    private static void testPredicates() {

        System.assertEquals(
            false,
            new AqResultBuilder().setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_SUCCESS)
                .createAqResult().hasError()
        );
        System.assertEquals(
            false,
            new AqResultBuilder().setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_INFORMATION)
                .createAqResult().hasError()
        );
        System.assertEquals(
            false,
            new AqResultBuilder().setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_WARNING)
                .createAqResult().hasError()
        );
        System.assertEquals(
            false,
            new AqResultBuilder().setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_PARTIAL_ERROR)
                .createAqResult().hasError()
        );
        System.assertEquals(
            true,
            new AqResultBuilder().setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_ERROR)
                .createAqResult().hasError()
        );

        System.assertEquals(
            false,
            new AqResultBuilder().setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_SUCCESS)
                .createAqResult()
                .severityAtLeast(AqResult.SEVERITY_WARNING)
        );
        System.assertEquals(
            true,
            new AqResultBuilder().setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_ERROR)
                .createAqResult()
                .severityAtLeast(AqResult.SEVERITY_WARNING)
        );

        System.assertEquals(
            false,
            AqResult.hasError(
                new List<AqResult>{
                    new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_SUCCESS).createAqResult(),
                    new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_WARNING).createAqResult()
                }
            )
        );
        System.assertEquals(
            true,
            AqResult.hasError(new List<AqResult>{
                new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult(),
                new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_WARNING).createAqResult()
            })
        );

    }

    @isTest
    private static void testToString() {

        String resultString = new AqResultBuilder()
            .setType(TEST_TYPE)
            .setSeverity(AqResult.SEVERITY_WARNING)
            .setLevel(AqResult.LEVEL_BUSINESS)
            .setMessage(TEST_MESSAGE)
            .setScopeType(TEST_SCOPE_TYPE)
            .setScope(TEST_SCOPE)
            .createAqResult().toString();

        System.assert(!String.isEmpty(resultString));

    }

    @isTest
    private static void testAddSubResult() {

        AqResult mainResult = new AqResultBuilder()
            .setType(TEST_TYPE)
            .setSeverity(AqResult.SEVERITY_SUCCESS)
            .createAqResult();

        mainResult.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult()
        );
        System.assertEquals(AqResult.SEVERITY_SUCCESS, mainResult.Severity);
        System.assertEquals(1, mainResult.SubResults.size());
        System.assertEquals(AqResult.SEVERITY_ERROR, mainResult.SubResults[0].Severity);

        mainResult.addSubResult(
            new AqResultBuilder().setType('SubResultType')
                .setScopeType('MyScopeType')
                .setScope('MyScope')
                .createAqResult()
        );
        System.assertEquals(AqResult.SEVERITY_SUCCESS, mainResult.Severity);
        System.assertEquals(2, mainResult.SubResults.size());
        System.assertEquals('SubResultType', mainResult.SubResults[1].Type);
        System.assertEquals('MyScopeType', mainResult.SubResults[1].ScopeType);
        System.assertEquals('MyScope', mainResult.SubResults[1].Scope);

        mainResult.addSubResultAndRollup(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult()
        );
        System.assertEquals(AqResult.SEVERITY_ERROR, mainResult.Severity);
        System.assertEquals(3, mainResult.SubResults.size());

    }

    //rollupSeverity() method
    @isTest
    private static void testRollupSeverity() {

        AqResult root = new AqResultBuilder().createAqResult();
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_INFORMATION).createAqResult()
        );
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_WARNING).createAqResult()
        );
        root.rollupSeverity();
        System.assertEquals(AqResult.SEVERITY_WARNING, root.Severity);

        root = new AqResultBuilder().createAqResult();
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult()
        );
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_INFORMATION).createAqResult()
        );
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_INFORMATION).createAqResult()
        );
        root.rollupSeverity();
        System.assertEquals(AqResult.SEVERITY_ERROR, root.Severity);

        //Mix success and error roll up to PARTIAL ERROR
        root = new AqResultBuilder().createAqResult();
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_SUCCESS).createAqResult()
        );
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult()
        );
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_SUCCESS).createAqResult()
        );
        root.rollupSeverity();
        System.assertEquals(AqResult.SEVERITY_PARTIAL_ERROR, root.Severity);

        //All errors roll up to ERROR
        root = new AqResultBuilder().createAqResult();
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult()
        );
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult()
        );
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult()
        );
        root.rollupSeverity();
        System.assertEquals(AqResult.SEVERITY_ERROR, root.Severity);

        //All-or-none
        //Mix success and error roll up to ERROR and SUCCESS changes to ABORTED
        root = new AqResultBuilder().createAqResult();
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_SUCCESS).createAqResult());
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_ERROR).createAqResult());
        root.addSubResult(
            new AqResultBuilder().setType(TEST_TYPE).setSeverity(AqResult.SEVERITY_SUCCESS).createAqResult());
        root.rollupSeverity(true, AqResult.SEVERITY_ABORTED);
        System.assertEquals(AqResult.SEVERITY_ERROR, root.Severity);
        System.assertEquals(AqResult.SEVERITY_ABORTED, root.SubResults[0].Severity);
        System.assertEquals(AqResult.SEVERITY_ABORTED, root.SubResults[2].Severity);
    }

    @isTest
    private static void testMergeResult() {

        AqResult mainResult = new AqResultBuilder()
            .setType(TEST_TYPE)
            .setSeverity(AqResult.SEVERITY_SUCCESS)
            .createAqResult();

        mainResult.addSubResult(
            new AqResultBuilder()
                .setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_SUCCESS)
                .setLevel(AqResult.LEVEL_BUSINESS)
                .setScopeType(TEST_SCOPE_TYPE)
                .setScope(TEST_SCOPE)
                .createAqResult()
        );
        mainResult.addSubResult(
            new AqResultBuilder()
                .setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_SUCCESS)
                .setLevel(AqResult.LEVEL_BUSINESS)
                .setScopeType(TEST_SCOPE_TYPE)
                .setScope(TEST_SCOPE)
                .createAqResult()
        );

        AqResult secondResult = new AqResultBuilder()
            .setScope(TEST_SCOPE)
            .createAqResult();

        secondResult.addSubResult(
            new AqResultBuilder()
                .setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_ERROR)
                .setLevel(AqResult.LEVEL_BUSINESS)
                .setScopeType(TEST_SCOPE_TYPE)
                .setScope('A')
                .createAqResult()
        );

        secondResult.addSubResult(
            new AqResultBuilder()
                .setType(TEST_TYPE)
                .setSeverity(AqResult.SEVERITY_SUCCESS)
                .setLevel(AqResult.LEVEL_BUSINESS)
                .setScopeType(TEST_SCOPE_TYPE)
                .setScope('B')
                .createAqResult()
        );

        //Merge adds parent scope to new sub results
        mainResult.mergeResult(secondResult);
        System.assertEquals(4, mainResult.SubResults.size());
        System.assertEquals(AqResult.SEVERITY_PARTIAL_ERROR, mainResult.Severity);
        System.assertEquals(TEST_SCOPE + '.A', mainResult.SubResults[2].Scope);
        System.assertEquals(TEST_SCOPE + '.B', mainResult.SubResults[3].Scope);

    }

    @isTest
    private static void testShield() {
        System.runAs(AqTest.adminUser) {
            try {
                Integer i = 1 / 0;
            } catch (System.Exception e) {

                AqResult resultUnshielded = new AqResultBuilder().setException(e).createAqResult();
                AqResult resultShielded = AqResult.shield(e);

                //Verify shielding
                System.assertEquals(AqResult.RESULT_TYPE_SHIELDED, resultShielded.Type);

                //Verify log was saved
                LogDgt__c log = AqLog.getMostRecent();
                System.assert(log != null);
                System.assertEquals(resultUnshielded.Message, log.Message__c);
            }

            //No shielding in debug mode
            Env__c env = Env__c.getInstance();
            env.DebugMode__c = true;
            upsert env;

            try {
                Integer i = 1 / 0;
            } catch (System.Exception e) {
                AqResult result = AqResult.shield(new AqResultBuilder().setException(e).createAqResult());
                System.assertEquals(e.getTypeName(), result.Type);
            }
        }
    }
}
