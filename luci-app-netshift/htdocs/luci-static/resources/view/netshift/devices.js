"use strict";
"require view";
"require uci";
"require ui";
"require network";
"require view.netshift.main as main";

// Local devices: route a LAN device (by source IP) fully through one section, or
// send it directly. The state lives in the sections' fully_routed_ips and in
// settings.routing_excluded_ips; the logic is in main.getDeviceRoute /
// main.setDeviceRoute (unit-tested), this view only draws it.

function readState() {
  const sections = {};

  uci.sections("netshift", "section").forEach((section) => {
    sections[section[".name"]] = main.toIpList(
      uci.get("netshift", section[".name"], "fully_routed_ips"),
    );
  });

  return {
    sections,
    excluded: main.toIpList(
      uci.get("netshift", "settings", "routing_excluded_ips"),
    ),
  };
}

function sameList(left, right) {
  return left.length === right.length && left.every((v, i) => v === right[i]);
}

// Write back only the lists that changed, so a section the user did not touch is
// never rewritten. An emptied list is removed instead of left as an empty option.
function writeState(before, after) {
  Object.keys(after.sections).forEach((name) => {
    if (sameList(before.sections[name] ?? [], after.sections[name])) {
      return;
    }

    uci.set(
      "netshift",
      name,
      "fully_routed_ips",
      after.sections[name].length ? after.sections[name] : null,
    );
  });

  if (!sameList(before.excluded, after.excluded)) {
    uci.set(
      "netshift",
      "settings",
      "routing_excluded_ips",
      after.excluded.length ? after.excluded : null,
    );
  }
}

function connectionSections() {
  return uci
    .sections("netshift", "section")
    .filter(
      (section) =>
        section.connection_type === "proxy" ||
        section.connection_type === "vpn",
    )
    .map((section) => section[".name"]);
}

function ipv4ToNumber(ip) {
  const parts = ip.split(".").map(Number);

  if (parts.length !== 4 || parts.some((n) => !Number.isInteger(n))) {
    return Number.MAX_SAFE_INTEGER;
  }

  return parts.reduce((total, n) => total * 256 + n, 0);
}

function collectDevices(hints, state) {
  const devices = new Map();

  hints.getMACHints().forEach(([mac, name]) => {
    const ip = hints.getIPAddrByMACAddr(mac);

    if (ip) {
      devices.set(ip, { ip, mac, name: name || "" });
    }
  });

  // Addresses that are in the lists but not on the network right now stay
  // visible, so they can be moved back to the default.
  main.listedDeviceIps(state).forEach((ip) => {
    if (!devices.has(ip)) {
      devices.set(ip, { ip, mac: "", name: "", offline: true });
    }
  });

  return [...devices.values()].sort(
    (a, b) => ipv4ToNumber(a.ip) - ipv4ToNumber(b.ip),
  );
}

function routeLabel(route) {
  if (route === main.DEVICE_ROUTE_DEFAULT) {
    return _("Default (by the lists)");
  }

  if (route === main.DEVICE_ROUTE_EXCLUDED) {
    return _("Direct (excluded from routing)");
  }

  return _("Everything through: %s").format(route);
}

const EntryPoint = {
  load() {
    return Promise.all([uci.load("netshift"), network.getHostHints()]);
  },

  render([, hints]) {
    main.injectGlobalStyles();

    const sections = connectionSections();
    const tableBody = E("tbody");

    const renderRows = () => {
      const state = readState();
      const routes = [main.DEVICE_ROUTE_DEFAULT, main.DEVICE_ROUTE_EXCLUDED]
        .concat(sections);

      tableBody.replaceChildren();

      collectDevices(hints, state).forEach((device) => {
        const current = main.getDeviceRoute(state, device.ip);
        const select = E(
          "select",
          {
            class: "cbi-input-select",
            change: (ev) => {
              const before = readState();
              const after = main.setDeviceRoute(before, device.ip, ev.target.value);

              writeState(before, after);
              renderRows();
            },
          },
          routes.map((route) =>
            E(
              "option",
              { value: route, selected: route === current ? "" : null },
              [routeLabel(route)],
            ),
          ),
        );

        tableBody.appendChild(
          E("tr", { class: "tr" }, [
            E("td", { class: "td" }, [
              device.name || (device.offline ? _("Not on the network") : "-"),
            ]),
            E("td", { class: "td" }, [device.ip]),
            E("td", { class: "td" }, [device.mac || "-"]),
            E("td", { class: "td" }, [select]),
          ]),
        );
      });
    };

    renderRows();

    return E("div", { class: "cbi-map" }, [
      E("h2", {}, [_("NetShift: local devices")]),
      E("div", { class: "cbi-map-descr" }, [
        _(
          "Choose how traffic of a device in your network is handled. A device can be sent completely through one section (all its traffic) or directly, ignoring the lists. Changes are applied with Save & Apply.",
        ),
      ]),
      E("div", { class: "cbi-section" }, [
        E("div", { class: "table" }, [
          E("table", { class: "table" }, [
            E("thead", {}, [
              E("tr", { class: "tr table-titles" }, [
                E("th", { class: "th" }, [_("Device")]),
                E("th", { class: "th" }, [_("IP address")]),
                E("th", { class: "th" }, [_("MAC address")]),
                E("th", { class: "th" }, [_("Routing")]),
              ]),
            ]),
            tableBody,
          ]),
        ]),
      ]),
    ]);
  },

  handleSave() {
    return uci.save();
  },

  handleSaveApply(ev) {
    return this.handleSave(ev).then(() => ui.changes.apply());
  },

  handleReset() {
    return uci.unload("netshift").then(() => window.location.reload());
  },
};

return view.extend(EntryPoint);
