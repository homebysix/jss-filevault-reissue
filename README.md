# Reissuing FileVault keys with the Casper Suite <!-- omit in toc -->

_Presented by Elliot Jordan, Senior Consultant, [Linde Group](http://www.lindegroup.com)_<br />_MacBrained - January 27, 2015 - San Francisco, CA_

## Deprecation Notice <!-- omit in toc -->

**[Escrow Buddy](https://github.com/macadmins/escrow-buddy) is a tool for reissuing and escrowing FileVault keys is available which does NOT require prompting users for their passwords.** As such, I don't plan to make any further updates to the workflow below. Please consider switching to Escrow Buddy. Read more below:

- Netflix Tech Blog: [Escrow Buddy: An open-source tool from Netflix for remediation of missing FileVault keys in MDM](https://netflixtechblog.com/escrow-buddy-an-open-source-tool-from-netflix-for-remediation-of-missing-filevault-keys-in-mdm-815aef5107cd)
- Elliot Jordan: [Escrowing new FileVault keys to MDM without password prompts](https://www.elliotjordan.com/posts/filevault-reissue/)

---

## Table of Contents <!-- omit in toc -->

<!-- MarkdownTOC autolink=true depth=4 bracket=round -->

- [Table of Contents](#table-of-contents)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
    - [Step One: Configuration Profile](#step-one-configuration-profile)
    - [Step Two: Smart Group](#step-two-smart-group)
    - [Step Three: Script](#step-three-script)
    - [Step Four: Policy](#step-four-policy)
    - [Follow Through](#follow-through)
    - [Compatibility](#compatibility)
        - [High Sierra (10.13) and Mojave (10.14)](#high-sierra-1013-and-mojave-1014)
        - [Catalina (10.15)](#catalina-1015)

<!-- /MarkdownTOC -->

---

## The Problem

__FileVault individual recovery keys can be missing from the JSS for many reasons.__

- Perhaps the Mac was encrypted prior to enrollment.
- The Mac was encrypted prior to the FileVault redirection profile installation.
- The original recovery key was lost for some reason (e.g. database corruption or a bug of some kind).

![FileVault is encrypted](images/problem1.png) &nbsp; ![FileVault is "not configured"](images/problem2.png)


## The Solution

__You can use a policy to generate a new FileVault key and upload to JSS.__

1. A configuration profile ensures that all FileVault keys are escrowed with the JSS.
2. A smart group determines which computers lack valid individual recovery keys.
3. Customize the __reissue_filevault_recovery_key.sh__ for your environment.
4. Create a policy that deploys the __reissue_filevault_recovery_key.sh__ script to the computers in the smart group.

![Notification](images/notification.png)

![Password Prompt](images/password_prompt.png)


### Step One: Configuration Profile

__A configuration profile called “Redirect FileVault keys to JSS” does what the name says.__

- General
    - Distribution Method: __Install Automatically__
    - Level: __Computer Level__
- FileVault Recovery Key Redirection
    - __Automatically redirect recovery keys to the JSS__
- Scope
    - __All computers__


### Step Two: Smart Group

__A smart group named “FileVault encryption key is invalid or unknown” selects the affected Macs.__

| And/Or |               Criteria                |       Operator       |              Value              |
| :----: | :-----------------------------------: | :------------------: | :-----------------------------: |
|        | FileVault 2 Individual Key Validation |        is not        |              Valid              |
|  and   |             Last Check-in             | less than x days ago |               30                |
|  and   |     FileVault 2 Detailed Status*      |          is          | FileVault 2 Encryption Complete |

<span style="font-size: 0.8em;">*From Rich Trouton’s FileVault status extension attribute: http://goo.gl/zB04LT</span>


### Step Three: Script

__The reissue_filevault_recovery_key.sh script runs on each affected Mac.__

- Start by customizing the __reissue_filevault_recovery_key.sh__ script as needed for your environment.
    - __Email__ affected employees to give them a heads up.
    - Use __jamfHelper__ to announce the upcoming password prompt.
    - Add __logo__ to AppleScript password prompt.
    - __Fail silently__ if logo files aren’t present, or any other problems detected.
    - __Verify__ the Mac login password, with 5 chances to enter correct password.

Here is the section of the script you'll want to customize:

![Script screenshot](images/script.png)


### Step Four: Policy

__A policy called “Reissue invalid or missing FileVault recovery key” runs the script on each Mac in the smart group.__

- General
    - Trigger: __Recurring Check-In__
    - Execution Frequency: __Once per computer__
- Packages
    - __AppleScriptCustomIcon.dmg__ (loads /tmp/Pinterest.icns)
- Scripts
    - __reissue_filevault_recovery_key.sh__ (priority: __After__)
- Scope
    - Smart Group: __FileVault encryption key is invalid or unknown__


### Follow Through

__Don’t forget to monitor policy logs and test FileVault recovery to verify success.__

- Monitor logs and flush one-off errors. (Unable to connect to distribution point, no user logged in, etc.)
- Identify and resolve remaining problems manually.
- Test a few newly-generated FileVault keys to ensure they are working as expected.
- Update your internal documentation.


### Compatibility

#### High Sierra (10.13) and Mojave (10.14)

This script appears to work with macOS High Sierra and Mojave, but there are a few known issues:

- On specific versions of High Sierra, entering an incorrect password during the key rotation process can result in invalidation of the existing FileVault key.
    - Since the existing FileVault key is not valid in the first place (presumably) this isn't the end of the world. But it means that if the key was stored separately, e.g. in a spreadsheet somewhere, it will no longer work.
    - We attempt to mitigate this by validating the provided password with `dscl` prior to using it for rotation of the FileVault key. However, there is no guarantee that your local account password and your FileVault password are the same.
- Previous versions of macOS generated log output that confirmed the successful escrow of the newly generated FileVault key. High Sierra and Mojave do not. Instead, a local file containing the new key is written, which MDM is meant to retrieve. We attempt to determine escrow success by detecting a change in that file, but it's not a guarantee of success.
- If you find additional issues with High Sierra or Mojave, I'd appreciate you [opening an issue](https://github.com/homebysix/jss-filevault-reissue/issues) on this repo.

#### Catalina (10.15)

This script should work on macOS Catalina, but please [open an issue](https://github.com/homebysix/jss-filevault-reissue/issues) if you notice any Catalina-specific bugs.


__Thank you!__


---

[See the original presentation slides](https://github.com/homebysix/misc/blob/master/2015-01-27%20MacBrained%20Reissuing%20FileVault%20Keys/MacBrained%20FileVault%20Reissue%20Slides.pdf).
