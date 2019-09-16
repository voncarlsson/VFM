# Changelog

## TBA, Version 0.5.4

* **List**:
    * Rested data will now display on the same line as XP.
    * Percentage done is no longer within parenthesis.
* **Miscellaneous**:
    * Added a cooldown of 5 seconds to progress requests per character.

## 2019-09-15, Version 0.5.3

* **XP/Hour**:
    * Will now track across levels.
    * Increased mean smoothing so that each individual data update contributes less to the result.
    * Corrected formula used to display estimated time to level up.
* **List**:
    * XP will now be digit grouped (e.g. "10,000" as opposed to "10000")
    * Data entry will now be output as single strings to avoid unnecessary amounts of timestamps being printed by addons like Prat.
* **Commands**:
    * Added command `interval`. This is a macro for `updatedelay`.
    * Updated help text to reflect above addition.
* **Miscellaneous**:
    * Changed the color used for the addon prefix when printing messages from a pale blue to a medium yellow.
    * Removed redundant sanity check.
    * General cleaning up of code.
    * Some rephrasing to either reduce length or increase ambiguity.
    * Player names will now be more nicely formatted and can be clicked to whisper that player.