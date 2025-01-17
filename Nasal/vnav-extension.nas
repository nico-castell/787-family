# IT-VNAV-Extension Controller v0.11.2
# Copyright (c) 2023 Nicolás Castellán (nico-castell)

var VnavMgr = {
    new: func() {
        props.globals.initNode("it-vnav/inputs/arm-button", 0, "BOOL");
        props.globals.initNode("it-vnav/inputs/cruise-button", 0, "BOOL");
        props.globals.initNode("it-vnav/inputs/descend-button", 0, "BOOL");
        props.globals.initNode("it-vnav/inputs/serviceable", 1, "BOOL");
        props.globals.initNode("it-vnav/inputs/rearm-ils", 0, "BOOL"); # The buttons in the MCP interact directly with this input.

        props.globals.initNode("it-vnav/internal/altitude-from", 0, "DOUBLE");
        props.globals.initNode("it-vnav/internal/captured", 0, "BOOL");
        props.globals.initNode("it-vnav/internal/capture-inhibit", 0, "BOOL");
        props.globals.initNode("it-vnav/internal/cruise-phase", 0, "BOOL");
        props.globals.initNode("it-vnav/internal/descent-authorized", 0, "BOOL");
        props.globals.initNode("it-vnav/internal/engaged", 0, "BOOL");
        props.globals.initNode("it-vnav/internal/last-vert", 0, "DOUBLE");
        props.globals.initNode("it-vnav/internal/block-descent", 0, "BOOL");
        props.globals.initNode("it-vnav/internal/vert-route-available", 0, "BOOL");

        props.globals.initNode("it-vnav/output/armed", 0, "BOOL");
        VnavMgr.handle_controller_text();
        VnavMgr.handle_steps_text();
        VnavMgr.handle_descent_text();
        VnavMgr.handle_auto_descend_text();
    },

    update_wp: func() {
        rte_avail = "it-vnav/internal/vert-route-available";

        index = getprop("autopilot/route-manager/current-wp");

        if (index == nil or index < 0) {
            setprop(rte_avail, 0);
            return;
        }

        target_ft = getprop("autopilot/route-manager/route/wp["~ index ~"]/altitude-ft");

        if (target_ft == nil or target_ft <= -9000) {
            setprop(rte_avail, 0);
            return;
        }

        setprop(rte_avail, 1);

        itaf_alt = "it-autoflight/input/alt";

        if (getprop(itaf_alt) != target_ft)
            setprop("it-vnav/internal/capture-inhibit", 0);

        setprop("it-vnav/internal/altitude-from", getprop(itaf_alt));

        if (getprop("it-vnav/internal/engaged") == 1)
            setprop(itaf_alt, target_ft);
    },

    handle_vnav_engagement: func() {
        if (getprop("it-vnav/internal/engaged")) {
            VnavMgr.update_wp();

            index = getprop("autopilot/route-manager/current-wp") - 1;
            if (index < 0)
                index = 0;

            old_ft = getprop("autopilot/route-manager/route/wp["~ index ~"]/altitude-ft");
            alt_from = "it-vnav/internal/altitude-from";

            if (getprop("it-autoflight/input/alt") == old_ft)
                setprop(alt_from, old_ft);
            else
                setprop(alt_from, getprop("instrumentation/altimeter/indicated-altitude-ft"));

            VnavMgr.handle_vert_path_change();

            return;
        }

        setprop("it-vnav/output/armed", 0);

        # Some aproaches end up creating very exact altitudes (eg. 2238 ft), we want to round to the
        # nearest 100 when VNAV disengages (2200 ft for example). The same goes for V/S.
        alt = "it-autoflight/input/alt";
        vs = "it-autoflight/input/vs";
        setprop(alt, math.round(getprop(alt), 100));
        setprop(vs, math.round(getprop(vs), 100));
    },

    handle_vert_path_change: func() {
        if (!getprop("it-vnav/internal/engaged"))
            return;

        descent = getprop("it-vnav/internal/descent");
        allowed = getprop("it-vnav/internal/descent-authorized") or getprop("it-vnav/settings/auto-descend");

        if (getprop("it-vnav/internal/cruise-phase") or !descent)
            setprop("it-vnav/internal/descent-authorized", 0);

        captured = getprop("it-vnav/internal/captured");
        capture_inhibit = getprop("it-vnav/internal/capture-inhibit");

        if (!captured and !capture_inhibit and (!descent or (descent and allowed)))
            if (getprop("it-vnav/internal/cruise-phase") or getprop("it-vnav/internal/steps"))
                setprop("it-autoflight/input/vert", 4);
            else
                setprop("it-autoflight/input/vert", 1);
    },

    handle_descent_change: func() {
        descent = getprop("it-vnav/internal/descent");
        allowed = getprop("it-vnav/internal/descent-authorized") or getprop("it-vnav/settings/auto-descend");

        if (descent and !allowed)
            setprop("it-vnav/internal/block-descent", 1);
        else
            setprop("it-vnav/internal/block-descent", 0);
    },

    handle_capturing_inhibitor: func() {
        setprop(
            "it-vnav/internal/capture-inhibit",
            getprop("it-autoflight/mode/vert") == "ALT CAP"
        );
    },

    handle_itaf_vert_change: func() {
        vnav_vert = "it-vnav/internal/last-vert";
        itaf_vert = "it-autoflight/input/vert";

        if (getprop("it-vnav/internal/engaged")) {
            if (getprop(vnav_vert) == 7)
                VnavMgr.handle_vert_path_change();

            if (getprop(itaf_vert) != 2 and getprop("it-vnav/inputs/rearm-ils"))
                setprop(itaf_vert, 2);
        }

        setprop(vnav_vert, getprop(itaf_vert));
    },

    cruise_button: func() {
        button = "it-vnav/inputs/cruise-button";
        if (!getprop(button))
            return;

        setprop("it-vnav/internal/altitude-from", getprop("it-autoflight/input/alt"));

        setprop(button, 0);
    },

    descend_button: func() {
        button = "it-vnav/inputs/descend-button";
        if (!getprop(button))
            return;

        # Only authorize descent when descending, but avoid if statement.
        setprop("it-vnav/internal/descent-authorized", getprop("it-vnav/internal/descent"));

        VnavMgr.handle_descent_change();
        VnavMgr.handle_vert_path_change();

        setprop(button, 0);
    },

    arm_button: func() {
        button = "it-vnav/inputs/arm-button";
        if (!getprop(button))
            return;

        engaged = "it-vnav/internal/engaged";
        armed = "it-vnav/output/armed";

        if (getprop(engaged) == 1 or getprop(armed) == 1) {
            setprop(button, 0);
            return;
        }

        lnav_engaged = getprop("it-autoflight/output/lat") == 1;
        lnav_armed = getprop("it-autoflight/output/lnav-armed");

        setprop(armed, lnav_armed or lnav_engaged);

        setprop(button, 0);
    },

    handle_controller_text: func() {
        text = "it-vnav/output/controller";

        if (getprop("it-vnav/internal/cruise-phase"))
            setprop(text, "CRUISE");
        else
            setprop(text, "TRANSITION");
    },

    handle_steps_text: func() {
        text = "it-vnav/output/steps";

        if (getprop("it-vnav/settings/steps"))
            setprop(text, "STEPS");
        else
            setprop(text, "NORMAL");
    },

    handle_descent_text: func() {
        text = "it-vnav/output/descent-type";

        if (getprop("it-vnav/settings/controlled-descent"))
            setprop(text, "CONTROLLED");
        else
            setprop(text, "FREE");
    },

    handle_auto_descend_text: func() {
        text = "it-vnav/output/auto-descend";

        if (getprop("it-vnav/settings/auto-descend"))
            setprop(text, "ON");
        else
            setprop(text, "OFF");
    }
};

setlistener("sim/signals/fdm-initialized", func {
    VnavMgr.new();

    setlistener(
        "autopilot/route-manager/current-wp",
        VnavMgr.update_wp,
    0, 0);

    setlistener(
        "it-vnav/internal/engaged",
        VnavMgr.handle_vnav_engagement,
    0, 0);

    setlistener(
        "it-vnav/internal/descent",
        VnavMgr.handle_descent_change,
    0, 0);

    setlistener(
        "it-vnav/internal/steps",
        VnavMgr.handle_vert_path_change,
    0, 0);

    setlistener(
        "it-vnav/internal/captured",
        VnavMgr.handle_vert_path_change,
    0, 0);

    setlistener(
        "it-vnav/internal/cruise-phase",
        VnavMgr.handle_vert_path_change,
    0, 0);

    setlistener(
        "it-autoflight/output/vert",
        VnavMgr.handle_itaf_vert_change,
    0, 0);

    setlistener(
        "it-autoflight/mode/vert",
        VnavMgr.handle_capturing_inhibitor,
    0, 0);

    setlistener(
        "it-vnav/inputs/cruise-button",
        VnavMgr.cruise_button,
    0, 0);

    setlistener(
        "it-vnav/inputs/descend-button",
        VnavMgr.descend_button,
    0, 0);

    setlistener(
        "it-vnav/inputs/arm-button",
        VnavMgr.arm_button,
    0, 0);

    setlistener(
        "it-vnav/internal/cruise-phase",
        VnavMgr.handle_controller_text,
    0, 0);

    setlistener(
        "it-vnav/settings/steps",
        VnavMgr.handle_steps_text,
    0, 0);

    setlistener(
        "it-vnav/settings/controlled-descent",
        VnavMgr.handle_descent_text,
    0, 0);

    setlistener(
        "it-vnav/settings/auto-descend",
        VnavMgr.handle_auto_descend_text,
    0 ,0);
});
