import AdaWalletsSetup_Container from '@salesforce/label/c.AdaWalletsSetup_Container';
import AdaWalletsSetup_Header_1 from '@salesforce/label/c.AdaWalletsSetup_Header_1';
import AdaWalletsSetup_Header_1_Info from '@salesforce/label/c.AdaWalletsSetup_Header_1_Info';
import AdaWalletsSetup_Success from '@salesforce/label/c.AdaWalletsSetup_Success';
import AdaWalletsSetup_Success_Info from '@salesforce/label/c.AdaWalletsSetup_Success_Info';

import AdaWalletsSetup_Config_Header from '@salesforce/label/c.AdaWalletsSetup_Config_Header';

import LoggingHeader from '@salesforce/label/c.LoggingHeader';
import LoggingTitle from '@salesforce/label/c.LoggingTitle';
import LoggingInfo from '@salesforce/label/c.LoggingInfo';
import LoggingEnableLogging from '@salesforce/label/c.LoggingEnableLogging';
import LoggingDisableLogging from '@salesforce/label/c.LoggingDisableLogging';
import LoggingSetupSuccess from '@salesforce/label/c.LoggingSetupSuccess';
import LoggingEnableSuccess from '@salesforce/label/c.LoggingEnableSuccess';
import LoggingDisableSuccess from '@salesforce/label/c.LoggingDisableSuccess';

import AdaWalletsSetup_PrivateKey_Sub_Header from '@salesforce/label/c.AdaWalletsSetup_PrivateKey_Sub_Header';
import AdaWalletsSetup_PrivateKey_Info from '@salesforce/label/c.AdaWalletsSetup_PrivateKey_Info';
import AdaWalletsSetup_PrivateKey_Button from '@salesforce/label/c.AdaWalletsSetup_PrivateKey_Button';


export const labels = {
    CORE: {
        Container: AdaWalletsSetup_Container,
        Header_1: AdaWalletsSetup_Header_1,
        Header_1_Info: AdaWalletsSetup_Header_1_Info,
        Success: AdaWalletsSetup_Success,
        Success_Info: AdaWalletsSetup_Success_Info
    },
    CONFIG: {
        Header: AdaWalletsSetup_Config_Header
    },
    LOGGING: {
        Header: LoggingHeader,
        Title: LoggingTitle,
        Info: LoggingInfo,
        EnableLogging: LoggingEnableLogging,
        DisableLogging: LoggingDisableLogging,
        SetupSuccess: LoggingSetupSuccess,
        EnableSuccess: LoggingEnableSuccess,
        DisableSuccess: LoggingDisableSuccess
    },
    PRIVATE_KEY: {
        Sub_Header: AdaWalletsSetup_PrivateKey_Sub_Header,
        Info: AdaWalletsSetup_PrivateKey_Info,
        Button: AdaWalletsSetup_PrivateKey_Button
    }
};
