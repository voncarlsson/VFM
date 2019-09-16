# VFM
VFM enables players to automatically share their current and rested XP with other characters of their choosing.

### A note on privacy

Data is **only** shared with characters currently on your whitelist. At no point will features be added, no matter how fancy or convenient, that wrestles power away from the user vis-à-vis their data.

## Commands

### Syntax
``/vfm command parameter``

Parameters surrounded by angular brackets (< >) are required. Parameters surrounded by square brackets ([ ]) are optional. A vertical bar ( | ) indicates multiple exclusive options.


#### Reset
Resets all data stored by VFM for the character issuing the command, including the whitelist.

#### List [all|recent|old|empty|requests]
Lists characters and their associated data.

* **All** - Prints all character data (but not requests).
* **Recent** - Default. Prints character data entries newer than 12-hours.
* **Old** - Prints character data entries older than 12-hours.
* **Empty** - Prints empty character data entries.
* **Requests** - Lists all pending requests that character has recieved.

#### Update \[_character name_\]
Broadcasts an update request on all possible channels (guild, party, raid, battleground). Does nothing if those channels are not available.

If a character name is specified, sends an update request to that one specific character. Works regardless of whether or not the character has access to above-mention channels.

The addon will automatically broadcast update requests. It is generally _not_ necessary for the player to issue this command.

#### Add \<_character name_\>
Whitelists a character and informs this to the character in question.

#### Remove \<_character name_\>
Removes a character from the whitelist.

#### Accept \<_index_\>
Accepts pending request with index \<_index_\>, adding that character to the whitelist.

#### Reject \<_index_\>
Rejects pending request with index \<_index_\>.

#### Updatedelay \<_number_\>

#### Interval \<_number_\>
Sets the delay between update request broadcasts to <number>. Default: 60. \<number\> must satisfy 10 <= x <= 600.

#### Pause
Pauses XP sharing with all characters.

### Unpause
Unpauses XP sharing if paused.

#### Debug
Toggles debug-mode on a session-basis. This is intended for developers (e.g. yours truly).