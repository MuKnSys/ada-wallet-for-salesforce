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

//Test methods for AqEnv.cls
@isTest
private with sharing class AqTest_AqEnv {

    @isTest
    private static void testProperties() {

        System.assert(AqEnv.CurrentOrg != null);
        System.assert(AqEnv.defaultTimeZoneSidKey != null);

        Boolean debugMode = AqEnv.isDebugMode;
        Boolean isSandbox = AqEnv.isSandbox;
        Boolean usingPicklists = AqEnv.IsUsingStateCountryPicklists;

    }

    //AqEnv.now() and AqEnv.today()
    @isTest
    private static void testDateTimeOverrides() {

        DateTime dtOverride1 = DateTime.now().addDays(10).addHours(6);
        DateTime dtOverride2 = DateTime.now().addDays(2).addHours(10);

        //Override datetime via setting
        Env__c env = Env__c.getInstance();
        env.NowOverride__c = dtOverride1;
        upsert env;

        System.assertEquals(dtOverride1, AqEnv.now());
        System.assertEquals(dtOverride1.date(), AqEnv.today());

        //Override datetime in execution context, takes precedence over setting
        AqEnv.nowOverride = dtOverride2;

        System.assertEquals(dtOverride2, AqEnv.now());
        System.assertEquals(dtOverride2.date(), AqEnv.today());

        //Reset, override date via setting
        AqEnv.nowOverride = null;
        env.NowOverride__c = null;
        env.TodayOverride__c = dtOverride1.date();
        upsert env;

        System.assertEquals(dtOverride1.date(), AqEnv.today());
        System.assertEquals(dtOverride1.date(), AqEnv.now().date());

        //Override date via execution context
        AqEnv.TodayOverride = dtOverride2.date();
        System.assertEquals(dtOverride2.date(), AqEnv.today());
        System.assertEquals(dtOverride2.date(), AqEnv.now().date());

        //Reset all
        AqEnv.nowOverride = null;
        AqEnv.TodayOverride = null;
        env.NowOverride__c = null;
        env.TodayOverride__c = null;
        upsert env;

        //Verify it's using real date and time
        System.assertEquals(Date.today(), AqEnv.today());
        System.assert(Math.abs(DateTime.now().getTime() - AqEnv.now().getTime()) < 5000);	//5 second factor for comparing times

    }

    //ifDebugMode()
    @isTest
    private static void testIfDebugMode() {

        //Not in debug mode
        System.assertEquals('', AqEnv.ifDebugMode('Add this'));

        //In debug mode
        Env__c env = Env__c.getOrgDefaults();
        env.DebugMode__c = true;
        insert env;
        System.assertEquals('Add this', AqEnv.ifDebugMode('Add this'));

    }

}
