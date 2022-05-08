
lappend auto_path ../src .

package require tclspotify

::spotify::callbackUserAuthState [list apply {{ } {

    set fp [open [file join [file dirname $::argv0] state.credentials] w]
    puts -nonewline $fp [::spotify::getUserAuthState]
    close $fp

}}]

if { ![file exists [file join [file dirname $argv0] state.credentials]] } {

    set fp [open [file join [file dirname $argv0] client.credentials] r]
    set client_id     [gets $fp]
    set client_secret [gets $fp]
    close $fp

    ::spotify::startUserAuthWebServer -port 12331
    ::spotify::runUserAuthLink -client_id $client_id -redirect_uri "http://localhost:12331/callback" -scope {user-modify-playback-state user-read-recently-played user-read-playback-position playlist-read-collaborative user-read-playback-state user-read-email user-read-currently-playing}
    set code [::spotify::checkUserAuthWebServer -timeout 120]
    ::spotify::stopUserAuthWebServer

    ::spotify::requestAccessToken -code $code -redirect_uri "http://localhost:12331/callback" -client_id $client_id -client_secret $client_secret

} {

    set fp [open [file join [file dirname $argv0] state.credentials] r]
    ::spotify::setUserAuthState [read $fp]
    close $fp

}

puts [::spotify::getCurrentUserProfile]

#puts ""
#puts ""

#dict for { k v } [::spotify::getPlaybackState] {
#    if { $k eq "item" } {
#
#        dict for { k1 v1 } $v {
#            puts "$k.$k1: $v1"
#        }
#
#    } {
#        puts "$k: $v"
#    }
#}

# device_id: XXX

puts [::spotify::startPlayback -device_id XXX]
