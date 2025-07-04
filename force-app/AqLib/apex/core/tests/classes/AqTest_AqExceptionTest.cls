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

//Unit tests for AqException.cls.
//Note: Added "Test" to end of name because Apex doesn't allow you to have class names ending in Exception unless they extend System.Exception.
@isTest
private with sharing class AqTest_AqExceptionTest {

    @isTest
    private static void test() {

        //Constructor
        AqException ae = new AqException('Code', 'ScopeType', 'Scope');
        System.assertEquals('Code', ae.Code);
        System.assertEquals('ScopeType', ae.ScopeType);
        System.assertEquals('Scope', ae.Scope);
        AqException.ExceptionDetail detail = ae.getDetail();
        detail = AqException.getExceptionDetail(ae);

        //Result constructor
        AqResult res = new AqResultBuilder()
            .setType('ResultType')
            .setSeverity(AqResult.SEVERITY_SUCCESS)
            .createAqResult();

        res.ScopeType = 'ScopeType';
        res.Scope = 'Scope';
        res.Code = 'Code';
        ae = new AqException(res);
        System.assertEquals('Code', ae.Code);
        System.assertEquals('Scope', ae.Scope);

        //Cause DML exception
        try {
            insert new TestObject__c();
            System.assert(false, 'Expected DmlException.');
        }
        catch (System.DmlException e) {

            detail = AqException.getExceptionDetail(e);
            AqException.DmlRowDetail dmlDetail = new AqException.DmlRowDetail(e, 0);
            System.assert(dmlDetail != null);

        }

        //Cause email exception
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{new Messaging.SingleEmailMessage()}, true);
            System.assert(false, 'Expected EmailException.');
        }
        catch (System.EmailException e) {

            detail = AqException.getExceptionDetail(e);
            AqException.DmlRowDetail emailDetail = new AqException.DmlRowDetail(e, 0);
            System.assert(emailDetail != null);

        }

    }

}
