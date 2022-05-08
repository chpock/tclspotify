# tclspotify - Tcl interface to Spotify WebAPI
# Copyright (C) 2022 Konstantin Kushnir <chpock@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

package require rest

if { $::tcl_platform(platform) eq "windows" } {

    package require twapi
    package require twapi_crypto

    http::register https 443 [list ::twapi::tls_socket]

}

package provide tclspotify 1.0.0

set _spotify(requestAccessToken) {
    url https://accounts.spotify.com/api/token
    method POST
    auth basic
    content-type application/x-www-form-urlencoded
    req_args { code: redirect_uri: }
    static_args { grant_type authorization_code }
}

set _spotify(refreshAccessToken) {
    url https://accounts.spotify.com/api/token
    method POST
    auth basic
    content-type application/x-www-form-urlencoded
    req_args { refresh_token: }
    static_args { grant_type refresh_token }
}

set _spotify(getCurrentUserProfile) {
    url https://api.spotify.com/v1/me
    headers { Authorization {Bearer %token%} }
    content-type application/json
}

set _spotify(getPlaybackState) {
    url https://api.spotify.com/v1/me/player
    headers { Authorization {Bearer %token%} }
    content-type application/json
    opt_args { additional_types: market: }
}

set _spotify(startPlayback) {
    url https://api.spotify.com/v1/me/player/play
    opt_args { device_id: }
    method PUT
    headers { Authorization {Bearer %token%} }
    content-type application/json
}

set _spotify(pausePlayback) {
    url https://api.spotify.com/v1/me/player/pause
    opt_args { device_id: }
    method PUT
    headers { Authorization {Bearer %token%} }
    content-type application/json
}

set _spotify(skipToNext) {
    url https://api.spotify.com/v1/me/player/next
    opt_args { device_id: }
    method POST
    headers { Authorization {Bearer %token%} }
    content-type application/json
}

set _spotify(skipToPrevious) {
    url https://api.spotify.com/v1/me/player/previous
    opt_args { device_id: }
    method POST
    headers { Authorization {Bearer %token%} }
    content-type application/json
}

rest::create_interface _spotify

namespace eval ::spotify {}

proc ::spotify::checkAccessToken { } {

    variable state

    if { [clock seconds] + 30 < $state(expires_in) } {
        return
    }

    refreshAccessToken

}

proc ::spotify::refreshAccessToken { args } {

    variable state
    variable stateCallback

    ::_spotify::basic_auth $state(client_id) $state(client_secret)

    set resp [::_spotify::refreshAccessToken -refresh_token $state(refresh_token)]

    array set state [list \
        access_token  [dict get $resp access_token] \
        expires_in    [expr { [clock seconds] + [dict get $resp expires_in] }] \
    ]

    if { [dict exists $resp refresh_token] } {
        set state(refresh_token) [dict get $resp refresh_token]
    }

    if { [dict exists $resp scope] } {
        set state(scope) [dict get $resp scope]
    }

    if { [info exists stateCallback] } {
        uplevel #0 $stateCallback
    }

    return $resp

}

proc ::spotify::requestAccessToken { args } {

    variable state
    variable stateCallback

    set query [lindex [::rest::parse_opts \
        { }       \
        { code: redirect_uri: client_id: client_secret: } \
        { }  \
        $args \
    ] 0]

    ::_spotify::basic_auth [dict get $query client_id] [dict get $query client_secret]

    set resp [::_spotify::requestAccessToken -code [dict get $query code] -redirect_uri [dict get $query redirect_uri]]

    unset -nocomplain state
    array set state [list \
        client_id     [dict get $query client_id] \
        client_secret [dict get $query client_secret] \
        refresh_token [dict get $resp refresh_token] \
        access_token  [dict get $resp access_token] \
        expires_in    [expr { [clock seconds] + [dict get $resp expires_in] }] \
    ]

    if { [dict exists $resp scope] } {
        set state(scope) [dict get $resp scope]
    }

    if { [info exists stateCallback] } {
        uplevel #0 $stateCallback
    }

    return $resp

}

proc ::spotify::getUserAuthLink { args } {

    set query [lindex [::rest::parse_opts \
        { response_type code }       \
        { client_id: redirect_uri: } \
        { scope: state: show_dialog: }  \
        $args \
    ] 0]

    return "https://accounts.spotify.com/authorize?[::http::formatQuery {*}$query]"

}

proc ::spotify::runUserAuthLink { args } {

    set link [getUserAuthLink {*}$args]

    if { $::tcl_platform(platform) eq "windows" } {
        ::twapi::shell_execute -path $link
    }

}

proc ::spotify::startUserAuthWebServer { args } {

    variable webServerSocket
    variable webServerResponse

    set params [lindex [::rest::parse_opts \
        {} \
        { port: } \
        { state: } \
        $args \
    ] 0]

    if { ![dict exists $params state] } {
        dict set params state ""
    }

    catch { close $webServerSocket }
    unset -nocomplain webServerResponse

    set webServerSocket [socket -server [list apply [list { state chan addr port } {

        set errMsg ""

        while { [set line [gets $chan]] ne "" } {

            set line [split $line]

            if { [lindex $line 0] ne "GET" } { continue }

            set resp [::rest::parameters [lindex $line 1]]

            if { [dict exists $resp error] } {
                set errMsg "Spotify error: [dict get $resp error]"
            } elseif { $state ne "" && ![dict exists $resp state] } {
                set errMsg "state not found in request"
            } elseif { $state eq "" && [dict exists $resp state] } {
                set errMsg "an empty state was expected"
            } elseif { $state ne "" && $state ne [dict get $resp state] } {
                set errMsg "state doesn't match"
            } elseif { ![dict exists $resp code] } {
                set errMsg "code not found in request"
            }

            set [namespace current]::webServerResponse [dict get $resp code]

        }

        puts $chan "HTTP/1.1 200 OK\nConnection: close\nContent-Type: text/plain\n\n"

        if { [info exists [namespace current]::webServerResponse] } {
            puts $chan "Authentication complete. You may now close this window."
        } {
            puts $chan "An error has occurred processing your login. Please try again. ERROR: $errMsg"
        }

        close $chan

    } [namespace current]] [dict get $params state]] [dict get $params port]]

}

proc ::spotify::stopUserAuthWebServer { } {

    variable webServerSocket

    catch { close $webServerSocket }

}

proc ::spotify::checkUserAuthWebServer { args } {

    variable webServerResponse

    set params [lindex [::rest::parse_opts {} {} { timeout } $args] 0]

    # default timeout is 120 seconds
    if { ![dict exists $params timeout] || [dict get $params timeout] eq "" } {
        dict set params timeout 120
    }

    if { [info exists webServerResponse] } {
        return $webServerResponse
    }

    after [expr { 1000 * [dict get $params timeout] }] [list set [namespace current]::webServerResponse ""]

    vwait [namespace current]::webServerResponse

    return $webServerResponse

}

proc ::spotify::getUserAuthState { } {
    variable state
    return [array get state]
}

proc ::spotify::setUserAuthState { v } {
    variable state
    unset -nocomplain state
    array set state $v
}

proc ::spotify::callbackUserAuthState { p } {
    variable stateCallback
    set stateCallback $p
}

foreach proc [info commands ::_spotify::*] {

    set proc [namespace tail $proc]

    if { [info commands ::spotify::$proc] eq "" } {

        proc ::spotify::$proc { args } {

            variable state

            checkAccessToken

            ::_spotify::set_static_args -token $state(access_token)

            set api [namespace tail [lindex [info level 0] 0]]

            # add body for POST/PUT methods. Spotify returns error for these
            # APIs if there is no content-length header:
            #
            # <title>411 Length Required</title>
            # <h1>Error: Length Required</h1><h2>POST requests require a <code>Content-length</code> header.</h2>
            #

            if { [dict exists $::_spotify($api) "method"] && ( [string tolower [dict get $::_spotify($api) "method"]] eq "post" || [string tolower [dict get $::_spotify($api) "method"]] eq "put" ) } {
                tailcall ::_spotify::$api {*}$args "" "{}"
            } else {
                tailcall ::_spotify::$api {*}$args
            }

        }

    }
}
