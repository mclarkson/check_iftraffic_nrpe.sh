#!/bin/bash
# Copyright(C) 2013 Mark Clarkson <mark.clarkson@smorg.co.uk>
#
# This software is provided under the terms of the GNU
# General Public License (GPL), as published at:
# http://www.gnu.org/licenses/gpl.html .
#
# File: check_iftraffic_nrpe.sh
# Date: 14 May 2013
# Version: 0.14
# Modified: 09 Feb 2014 (Mark Clarkson)
#           Added check for negative bandwidth.
#           07 Mar 2014 (Mark Clarkson)
#           Fixed perpetual 'Got first data sample' problem
#           18 Feb 2015 (Mark Clarkson)
#           Also check for the 'date' command.
#           13 Apr 2015 (Mark Clarkson)
#           New option '-u' changes unkown errors into warning errors.
#
# Purpose: Check and stat a number of network interfaces.
#
# Notes:
#


# ---------------------------------------------------------------------------
# DEFAULTS (Change as necessary)
# ---------------------------------------------------------------------------

# The interface statistics are cached in IFCACHEPREFIX.<username>.cache
IFCACHEPREFIX="/var/tmp/check_iftraffic_nrpe_sh"

# ---------------------------------------------------------------------------
# DON'T TOUCH ANYTHING BELOW
# ---------------------------------------------------------------------------

ME="$0"
CMDLINE="$@"
TRUE=1
FALSE=0
VERSION="0.12"
OK=0
WARN=1
CRIT=2
UNKN=3
UNKNOWN="UNKNOWN"

UNSET=99
EXCLUDE=0
INCLUDE=1

NOTYPE=99
BOND=1
ETH=2
BRIDGE=3
VLAN=4

INCL="."
EXCL="."
PERF=
NOPERF="WoNtMaTcHaDaRnThInG"
MINCL="WoNtMaTcHaDaRnThInG"
DEVF="/proc/net/dev"
SYSD="/sys/class/net"
VLAND="/proc/net/vlan"
IFCACHE=
MESSAGE=
MATCHID=

declare -i WITHPERF=0 PRUNESLAVES=0 CHECKBOND=0 PRUNEDOWN=0 SEMIAUTO=0
declare -i USEBYTES=0 IFSPEED=100 WARNPC=0 WARNVAL=0 BRIEF=0

declare -a IFL         # Interface list 
declare -a IFLL        # Interface list last (from cache)
declare -a IFD         # Interface data 
declare -ia IFshow     # Interface status (included or excluded)
declare -ia IFtype     # Interface type (bond,eth,bridge,vlan)
declare -ia rx tx ts   # Bytes read written, epoch time
declare -ia IFdown     # The interface is up or down
declare -ia IFsbu      # The interface should-be-up
declare -ia IFbwe      # Bandwidth Exceeded

# ---------------------------------------------------------------------------
main()
# ---------------------------------------------------------------------------
{
    local -i i bwe=0
    local nfiles=0 a= SPC= b= SPCB=

    retval=$OK

    parse_options "$@"

    sanity_checks

    IFCACHE="$IFCACHEPREFIX.$MATCHID.`id -un`.cache"

    do_check

    txt="OK:"

    IS=" is"
    for (( i=0 ; i<${#IFL[*]} ; ++i ))
    do
        [[ ${IFbwe[i]} -eq 1 ]] && {
            b+="$SPCB${IFL[i]}"
            SPCB=", "
            bwe=1
            [[ $retval == $OK ]] && {
                txt="WARNING:"
                retval=$WARN
            }
        }
        [[ ${IFsbu[i]} -eq 1 ]] && {
            [[ -n $SPC ]] && IS=", are"
            a+="$SPC${IFL[i]}"
            txt="CRITICAL:"
            retval=$CRIT
            SPC=", "
        }
    done
    [[ -n $a ]] && ALERT="$a$IS DOWN. "
    [[ $bwe -eq 1 ]] && {
        if [[ $BRIEF -eq 1 ]]; then
            ALERT+="Bandwidth threshold exceeded. "
        else
            ALERT+="Bandwidth threshold exceeded for $b. "
        fi
    }

    if [[ $BRIEF -eq 1 ]]; then
        [[ $WITHPERF -eq 0 ]] && out="$txt ${ALERT}"
        [[ $WITHPERF -eq 1 ]] && out="$txt ${ALERT}See graphs for stats."
    else
        out="$txt ${ALERT}Stats: $MESSAGE"
    fi

    [[ $WITHPERF -eq 1 ]] && {
        out+=" | $PERF"
    }

    printf "$out\n"

    exit $retval
}

# ---------------------------------------------------------------------------
sanity_checks()
# ---------------------------------------------------------------------------
{
    local i

    for i in "$DEVF" "$SYSD"; do
        [[ ! -r $i ]] && {
            echo "$UNKNOWN: Cannot access '$i'. Proc or sys not mounted?"
            exit 3
        }
    done

    for binary in grep sed dd id date; do
        if ! which $binary >& /dev/null; then
            echo "$UNKNOWN: $binary binary not found in path. Aborting."
            exit $UNKN
        fi
    done

    [[ -e $IFCACHE && ! -w $IFCACHE ]] && {
        echo "$UNKNOWN: Cache file is not writable. Delete '$IFCACHE'."
        exit $UNKN
    }

    [[ $IFSPEED -eq 0 ]] && {
        echo "$UNKNOWN: Invalid interface speed specified ($IFSPEED)"
        exit $UNKN
    }
}

# ----------------------------------------------------------------------------
usage()
# ----------------------------------------------------------------------------
{
    echo
    echo "`basename $ME` - Interface statistics plugin."
    echo
    echo "Usage: `basename $ME` [options]"
    echo
    echo " -h      : Display this help text."
    echo " -i REGX : Include the interface(s) matched by the REGX regular"
    echo "           expression. Defaults to showing all interfaces."
    echo "           Specify this option multiple times to add more."
    echo " -x REGX : Exclude the interface(s) matched by the REGX regular"
    echo "           expression. Defaults to excluding none. Excludes"
    echo "           will override any includes."
    echo "           Specify this option multiple times to add more."
    echo " -k      : Don't include the slaves of bond devices or bond"
    echo "           devices with no slaves."
    echo " -p      : Include performance data (for graphing)."
    echo " -b      : Brief - exclude stats in status message. Useful for"
    echo "           systems with many interfaces where a large status"
    echo "           message might cause truncation of the performance data."
    echo " -I NAME : Interface that must always be included. This is not a"
    echo "           regular expression - it should match one interface only."
    echo "           Emits warning if an interface specified here is down."
    echo "           Specify this option multiple times to add more."
    echo " -a      : Semi automatic. This will try to work out if the"
    echo "           interface is intentionally down or not and alert in"
    echo "           the latter case. For example, if the administrator"
    echo "           did 'ip li set eth2 up' then it would alert when down,"
    echo "           but if instead 'ip li set eth2 down' then there would"
    echo "           be no alert; the loopback device should always be up."
    echo " -d      : Exclude devices which are down, unless specifically"
    echo "           included with '-I', in which case, a warning will be"
    echo "           issued that the interface is down."
    echo " -D NAME : Don't include performance stats for NAME interface."
    echo " -B      : Use bytes/s instead of bits/s in message output."
    echo " -s      : The interface speed in Mbits/s. This will be set the"
    echo "           same for all selected interfaces. E.g. 1, 5, 10, 100."
    echo "           Default is 100."
    echo " -w NUM  : Warning threshold percentage. Warn when bandwidth"
    echo "           usage exceeds NUM percent of the maximum. Interfaces"
    echo "           in the '-D', no performance stats, list will not be"
    echo "           checked. Default is 0, which also means, off."
    #echo " -b      : Check bond devices for errors; Alerts if:"
    #echo "              - A bond has no slave devices."
    echo " -m NUM  : MatchID. Adds the match ID to the cache file name."
    echo "           This allows the plugin to be run for different"
    echo "           checks or from multiple servers."
    echo " -u      : Unknown errors are changed to warning errors."
    echo
    echo "Examples:"
    echo
    echo " Check all interfaces:"
    echo
    echo " ./`basename $ME`"
    echo
    echo " Show when loopback is down but don't create performance stats"
    echo " for it:"
    echo
    echo " ./`basename $ME` -D lo -p"
    echo
    echo " Show when loopback is down but don't create performance stats"
    echo " for it, create performance stats for everything else, don't"
    echo " show slaves of bond devices or downed interfaces:"
    echo
    echo " ./`basename $ME` -D lo -p -k -d"
    echo
    echo " Same as previous but use the smarter '-a' instead of '-d'."
    echo " If the admin set the interface to be up but the interface is"
    echo " down then an alert will be raised."
    echo
    echo " ./`basename $ME` -D lo -p -k -a"
    echo
    echo " Same as previous but assume all interfaces are 100mbit and"
    echo " alert if either inboud or outbound traffic exceeds 95%."
    echo
    echo " ./`basename $ME` -D lo -p -k -a -s 100 -w 95"
    echo
}

# ---------------------------------------------------------------------------
fill_netdev_iflist()
# ---------------------------------------------------------------------------
{
    local IF DATA data

    while read IF DATA ; do
        data=`echo "$DATA" | sed 's/  */ /g'`
        IFL+=("$IF")
        IFD+=("$data")
    done < <(grep : $DEVF | tr : " ")
}

# ---------------------------------------------------------------------------
prune_iflist()
# ---------------------------------------------------------------------------
{
    local t
    local -i i=0 b=0

    for (( i=0 ; i<${#IFL[*]} ; ++i ))
    do
        IFshow[i]=$UNSET
        IFdown[i]=0
        IFsbu[i]=0
        # include and exclude processing
        if [[ $INCL == "." && $EXCL == "." ]]; then
            IFshow[i]=$INCLUDE
        elif [[ $INCL != "." && $EXCL == "." ]]; then
            IFshow[i]=$EXCLUDE
            echo "${IFL[i]}" | grep -qsE "$INCL" && IFshow[i]=$INCLUDE
        elif [[ $INCL == "." && $EXCL != "." ]]; then
            IFshow[i]=$INCLUDE
            echo "${IFL[i]}" | grep -qsE "$EXCL" && IFshow[i]=$EXCLUDE
        elif [[ $INCL != "." && $EXCL != "." ]]; then
            echo "${IFL[i]}" | grep -qsE "$INCL" && IFshow[i]=$INCLUDE
            echo "${IFL[i]}" | grep -qsE "$EXCL" && IFshow[i]=$EXCLUDE
        fi
        # exclude down interfaces
        [[ $PRUNEDOWN -eq 1 ]] && {
            t="`cat $SYSD/${IFL[i]}/operstate`"
            [[ $t == "down" ]] && {
                IFshow[i]=$EXCLUDE
                IFdown[i]=1
            }
        }
        # slave exclusions
        [[ $PRUNESLAVES -eq 1 ]] && {
            [[ -d "$SYSD/${IFL[i]}/master" ]] && IFshow[i]=$EXCLUDE
        }
        # add must-include interfaces
        echo "${IFL[i]}" | grep -m1 -qsE "$MINCL" && {
            IFshow[i]=$INCLUDE
            [[ ${IFdown[i]} -eq 1 ]] && {
                IFsbu[i]=1
            }
        }
        [[ $SEMIAUTO -eq 1 ]] && {
            # /sys/.../ethX/carrier - 0 byte read when in ADMIN down.
            # /sys/.../ethX/carrier - >0 byte read when in ADMIN up.
            b=`dd if=$SYSD/${IFL[i]}/carrier bs=1 count=1 2>/dev/null | wc -c`
            if [[ ${IFL[i]} == "lo" ]]; then
                # Special case for loopback - should always be up.
                t="`cat $SYSD/${IFL[i]}/operstate`"
                [[ $t == "down" ]] && {
                    IFdown[i]=1
                    IFsbu[i]=1
                }
            elif [[ $b -eq 1 ]]; then
                # This is an ADMIN UP interface
                b=`cat $SYSD/${IFL[i]}/carrier`
                [[ $b -eq 0 ]] && {
                    # No carrier for admin up interface.
                    #MESSAGE+="Interface ${IFL[i]} is down. "
                    IFsbu[i]=1
                }
            else
                IFshow[i]=$EXCLUDE
            fi
        }
        # categorise if interface was included above
        [[ ${IFshow[i]} -eq $INCLUDE ]] && {
            # Defaults to device being an eth device.. hmm..
            IFtype[i]=$ETH
            [[ -d "$SYSD/${IFL[i]}/bonding" ]] && IFtype[i]=$BOND
            [[ -d "$SYSD/${IFL[i]}/bridge" ]] && IFtype[i]=$BRIDGE
            [[ -f "$VLAND/${IFL[i]}" ]] && IFtype[i]=$VLAN
        }
    done
}

# ---------------------------------------------------------------------------
read_iflist_stats_from_file()
# ---------------------------------------------------------------------------
{
    local IF RX TX TIME x

    while read IF RX TX TIME x; do
        IFLL+=("$IF")
        rx+=("$RX")
        tx+=("$TX")
        ts+=("$TIME")
    done <$IFCACHE
}

# ---------------------------------------------------------------------------
write_iflist_stats_to_file()
# ---------------------------------------------------------------------------
{
    local rx tx t time=`date +%s`

    # Write all the stats; unfiltered.
    for (( i=0 ; i<${#IFshow[*]} ; ++i ))
    do
        rx=`echo "${IFD[i]}" | cut -d " " -f 1`
        tx=`echo "${IFD[i]}" | cut -d " " -f 9`
        t+="${IFL[i]} $rx $tx $time\n"
    done

    printf "$t" >$IFCACHE
}

# ---------------------------------------------------------------------------
do_check()
# ---------------------------------------------------------------------------
{
    local -i now i rxl txl deltarx deltatx deltats bpsrx bpstx kbpstx kbpsrx
    local t
    local -i minus_values=0

    fill_netdev_iflist

    prune_iflist

    if [[ -e $IFCACHE ]]; then
        read_iflist_stats_from_file
    else
        write_iflist_stats_to_file
        echo "OK: Got first data sample."
        exit $OK
    fi

    now=`date +%s`

    for (( i=0 ; i<${#IFshow[*]} ; ++i ))
    do
        # Only process selected interfaces
        [[ ${IFshow[i]} -ne $INCLUDE ]] && continue
        [[ ${IFL[i]} != ${IFLL[i]} ]] && {
            # Something has changed. Pretend this is the first time again.
            write_iflist_stats_to_file
            echo "WARNING: Interfaces changed. Got first sample, again."
            exit $WARN
        }
        rxl=`echo "${IFD[i]}" | cut -d " " -f 1`
        txl=`echo "${IFD[i]}" | cut -d " " -f 9`
        deltarx=$(($rxl-${rx[i]}))
        deltatx=$(($txl-${tx[i]}))
        deltats=$((now-${ts[i]}))
        [[ $deltats -le 0 ]] && {
            echo "$UNKNOWN: Invalid time delta ($deltats). Aborting."
            exit $UNKN
        }
        # Bytes per second (perf output)
        Bpsrx=$((deltarx/deltats))
        Bpstx=$((deltatx/deltats))
        bpsrx=$((Bpsrx*8))
        bpstx=$((Bpstx*8))
        if [[ $USEBYTES -eq 0 ]]; then
            # Kilo-bits per second (message output)
            rx=$bpsrx ; ur=""
            tx=$bpstx ; ut=""
            [[ $bpsrx -gt 1100 ]] && { rx=$(($bpsrx/1024)); ur="k"; }
            [[ $bpstx -gt 1100 ]] && { tx=$(($bpstx/1024)); ut="k"; }
            [[ $ur = "k" && $bpsrx -gt $((1100*1024)) ]] && \
                { rx=$(($rx/1024)); ur="M"; }
            [[ $ut = "k" && $bpstx -gt $((1100*1024)) ]] && \
                { tx=$(($tx/1024)); ut="M"; }
            MESSAGE+="${IFL[i]}(${rx}$ur/${tx}$ut) "
        else
            # Bytes per second (message output)
            rx=$Bpsrx ; ur=""
            tx=$Bpstx ; ut=""
            [[ $Bpsrx -gt 1100 ]] && { rx=$(($Bpsrx/1024)); ur="k"; }
            [[ $Bpstx -gt 1100 ]] && { tx=$(($Bpstx/1024)); ut="k"; }
            [[ $ur = "k" && $Bpsrx -gt $((1100*1024)) ]] && \
                { rx=$(($rx/1024)); ur="M"; }
            [[ $ut = "k" && $Bpstx -gt $((1100*1024)) ]] && \
                { tx=$(($tx/1024)); ut="M"; }
            MESSAGE+="${IFL[i]}(${rx}$ur/${tx}$ut) "
        fi
        # Is interface in NOPERF list
        echo "${IFL[i]}" | grep -qsE "$NOPERF" || {
            # Check bandwidth
            [[ $WARNVAL -gt 0 ]] && {
                [[ $bpsrx -gt $WARNVAL ||
                   $bpstx -gt $WARNVAL ]] && {
                    IFbwe[i]=1
                }
            }
            PERF+="in-${IFL[i]}=${Bpsrx} out-${IFL[i]}=${Bpstx} "
        }

        # Check for negative value. Happens after reboot or rollover.
        [[ $Bpstx -lt 0 || $Bpsrx -lt 0 ]] && {
            minus_values=1
        }

    done

    # Check for negative value. Happens after reboot or rollover.
    [[ $minus_values -eq 1 ]] && {
        write_iflist_stats_to_file
        echo "OK: Got first data sample."
        exit $OK
    }

    if [[ $USEBYTES -eq 0 ]]; then
        MESSAGE+="(in/out in bits/s)"
    else
        MESSAGE+="(in/out in bytes/s)"
    fi

    write_iflist_stats_to_file
}

# ----------------------------------------------------------------------------
parse_options()
# ----------------------------------------------------------------------------
# Purpose: Parse program options and set globals.
# Arguments: None
# Returns: Nothing
{
    set -- $CMDLINE
    while true
    do
    case $1 in
            -i) if [[ $INCL = "." ]]; then
                    INCL="$2"
                else
                    INCL+="|$2"
                fi
                shift
            ;;
            -I) if [[ $MINCL = "WoNtMaTcHaDaRnThInG" ]]; then
                    MINCL="^$2$"
                else
                    MINCL+="|^$2$"
                fi
                shift
            ;;
            -x) if [[ $EXCL = "." ]]; then
                    EXCL="$2"
                else
                    EXCL+="|$2"
                fi
                shift
            ;;
            -D) if [[ $NOPERF = "WoNtMaTcHaDaRnThInG" ]]; then
                    NOPERF="$2"
                else
                    NOPERF+="|$2"
                fi
                shift
            ;;
            -m) MATCHID="$2"
                shift
            ;;
            -s) IFSPEED="$2"
                : $((IFSPEED++))
                : $((IFSPEED--))
                shift
            ;;
            -w) WARNPC="$2"
                : $((WARNPC++))
                : $((WARNPC--))
                [[ $WARNPC -lt 0 ]] && WARNPC=0
                [[ $WARNPC -gt 100 ]] && WARNPC=100
                shift
            ;;
            -p) WITHPERF=1
            ;;
            -b) BRIEF=1
            ;;
            -d) PRUNEDOWN=1
            ;;
            -k) PRUNESLAVES=1
            ;;
            -b) CHECKBOND=1
            ;;
            -B) USEBYTES=1
            ;;
            -a) SEMIAUTO=1
            ;;
            -u) UNKN=1; UNKNOWN="WARNING"
            ;;
            -h) usage
                exit 0
            ;;
            ?*) usage
                echo -e "\nInvalid option '$1'\n"
                exit 4
            ;;
        esac
    shift 1 || break
    done

    IFSPEED=$((IFSPEED*1024*1024))
    [[ $WARNPC -gt 0 ]] && WARNVAL=$((($WARNPC*$IFSPEED)/100))
}

main "$@"

exit 0
