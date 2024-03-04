// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

enum Constants {
    enum Global {
        static let INSTRUMENTATION_NAME = "middleware-ios"
        static let VERSION_STRING = "1.0.1"
        static let UNKNOWN_APP_NAME = "unknown-app"
    }
    
    enum Attributes {
        static let APP = "app"
        static let APP_VERSION = "app.version"
        static let RUM_SDK_VERSION = "rum.sdk.version"
        static let DEVICE_MODEL_NAME = "device.model.name"
        static let ERROR = "error"
        static let COUNT = "count"
        static let EVENT_TYPE = "event.type"
        static let OS_NAME = "os.name"
        static let OS_VERSION = "os.version"
        static let SESSION_ID = "session.id"
        static let PREVIOUS_SESSION_ID = "previous.session.id"
        static let EXCEPTION_MESSAGE = "exception.message"
        static let EXCEPTION_TYPE = "exception.type"
        static let EXCEPTION_STACKTRACE = "exception.stacktrace"
        static let LAST_SCREEN_NAME = "last.screen.name"
        static let SCREEN_NAME = "screen.name"
        static let THREAD_NAME = "thread.name"
        static let CONFIG_SETTINGS = "config_settings"
        static let COMPONENT = "component"
        static let OBJECT_TYPE = "object.type"
        static let SENDER_TYPE = "sender.type"
        static let TARGET_TYPE = "target.type"
        static let ACTION_NAME = "action.name"
        static let LINK_TRACE_ID = "link.traceId"
        static let LINK_SPAN_ID = "link.spanId"
        static let HTTP_URL = "http.url"
        static let HTTP_METHOD = "http.method"
        static let HTTP_STATUS_CODE = "http.status_code"
        static let HTTP_RESPONSE_CONTENT_LENGTH_UNCOMPRESSESD = "http.response_content_length_uncompressed"
        static let HTTP_REQUEST_CONTENT_LENGTH = "http.request_content_length"
        static let NET_HOST_CONNECTION_TYPE = "net.host.connection.type"
        static let NET_HOST_CONNECTION_SUBTYPE = "net.host.connection.subtype"
        static let NET_HOST_CARRIER_NAME = "net.host.carrier.name"
        static let NET_HOST_CARRIER_MCC = "net.host.carrier.mcc"
        static let NET_HOST_CARRIER_MNC = "net.host.carrier.mnc"
        static let NET_HOST_CARRIER_ICC = "net.host.carrier.icc"
    }
    enum Events {
        static let PROCESS_START = "process.start"
    }
    enum Spans {
        static let SESSION_ID_CHANGE = "session.id.change"
        static let RESIGNACTIVE = "ResignActive"
        static let ENTER_FOREGROUND = "EnterForeground"
        static let ACTION = "action"
        static let PRESENTATION_TRANSITION = "PresentationTransition"
        static let APP_START = "AppStart"
        static let APP_TERMINATING = "AppTerminating"
        static let SHOW_VC = "ShowVC"
    }
    
    enum LifeCycleEvents {
        static let UI_APPLICATION_WILL_RESIGN_ACTIVE_NOTIFICATION = "UIApplicationWillResignActiveNotification"
        static let UI_APPLICATION_SUSPENDED_EVENTS_ONLY_NOTIFICATION = "UIApplicationSuspendedEventsOnlyNotification"
        static let UI_APPLICATION_DID_ENTER_BACKGROUND_NOTIFICATION = "UIApplicationDidEnterBackgroundNotification"
        static let UI_APPLICATION_WILL_ENTER_FOREGROUND_NOTIFICATION = "UIApplicationWillEnterForegroundNotification"
        static let UI_APPLICATION_DID_BECOME_ACTIVE_ACTIVE_NOTIFICATION = "UIApplicationDidBecomeActiveNotification"
        static let UI_APPLICATION_SUSPENDED_NOTIFICATION = "UIApplicationSuspendedNotification"
        static let UI_APPLICATION_WILL_TERMINATE_NOTIFICATION = "UIApplicationWillTerminateNotification"
        
    }
}

