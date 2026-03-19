# My custom shell configuration
export PATH="/usr/local/bin:$PATH"

# Added by some tool
alias myalias='echo hello'

# Pre-NoMOOP openclaw lines (should be migrated)
alias openclaw='bash /old/path/scripts/openclaw.sh'
alias n8n-token='security find-generic-password -a "openclaw" -s "n8n-gateway-bearer" -w'

# This comment mentions openclaw but should NOT be migrated
# Another custom thing
export EDITOR=vim
