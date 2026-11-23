import Toybox.Application;
import Toybox.WatchUi;

class MarsApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new MarsFace()];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
