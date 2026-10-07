"""App-owned data declarations for the optional Apple/Firestore build.

SDK manifests remain bundled separately; this covers the app's own sync data.
Location, recordings and transcripts remain local and are not declared uploaded.
"""
ACCOUNT_DATA_TYPES = (
    'NSPrivacyCollectedDataTypeName',
    'NSPrivacyCollectedDataTypeEmailAddress',
    'NSPrivacyCollectedDataTypeUserID',
    'NSPrivacyCollectedDataTypeDeviceID',
    'NSPrivacyCollectedDataTypeOtherUserContent',
    'NSPrivacyCollectedDataTypeProductInteraction',
)

def configure(manifest, accounts):
    result = dict(manifest)
    result['NSPrivacyTracking'] = False
    result['NSPrivacyTrackingDomains'] = []
    result['NSPrivacyCollectedDataTypes'] = [
        {'NSPrivacyCollectedDataType': kind,
         'NSPrivacyCollectedDataTypeLinked': True,
         'NSPrivacyCollectedDataTypeTracking': False,
         'NSPrivacyCollectedDataTypePurposes': ['NSPrivacyCollectedDataTypePurposeAppFunctionality']}
        for kind in ACCOUNT_DATA_TYPES
    ] if accounts else []
    return result

def validate_accounts(manifest):
    if manifest != configure(manifest, True):
        raise ValueError('Account privacy manifest does not declare the app-owned identity and optional sync data')
