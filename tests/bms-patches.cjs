// Run production methods with GI boundaries replaced; no Shell session required.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = process.argv[2];
function load(file, expression, globals = {}) {
    const source = fs.readFileSync(path.join(root, file), 'utf8')
        .replace(/^import\s[\s\S]*?;\s*$/gm, '')
        .replace(/export default class /g, 'class ')
        .replace(/export /g, '');
    return vm.runInNewContext(source + '\n' + expression, globals);
}
let failures = 0;
function test(name, fn) {
    try { fn(); console.log('PASS', name); }
    catch (error) { failures++; console.error('FAIL', name, error.message); }
}
class BlurEffect { static supports_corner_radius = false; }
class CornerEffect {}
const Stacks = load('src/components/popup/message_stacks.js', 'PopupBlurMessageStacks', {
    NativeDynamicBlurEffect: BlurEffect, CornerEffect,
});
test('history cards get fallback corners and release both effects', () => {
    const stacks = new Stacks(null, {popup: {NOTIFICATION: true, SIGMA: 30, NOTIFICATION_CORNER_RADIUS: 20}});
    const effects = new Map();
    const card = {
        has_style_class_name: () => false,
        get_effect: name => effects.get(name),
        add_effect_with_name: (name, effect) => effects.set(name, effect),
        remove_effect_by_name: name => effects.delete(name),
    };
    stacks.attach_blur(card);
    assert.equal(effects.size, 2, 'fallback must install blur and corner effects');
    stacks.detach_blur(card);
    assert.equal(effects.size, 0, 'both effects must be removed');
});
const ExtensionClass = load('src/extension.js', 'BlurMyShell', {Extension: class {}});
const pending = [];
const PopupClass = load('src/components/popup/index.js', 'PopupBlur', {
    GLib: {idle_add: (_priority, callback) => { pending.push(callback); return pending.length; }},
});
for (const notification of [false, true]) {
    test(`popup toggle retargets surfaces (notifications=${notification})`, () => {
        const callbacks = {};
        const component = name => new Proxy({}, {get: (_object, key) => {
            if (key.endsWith('_changed')) return fn => { callbacks[name + '.' + key] = fn; };
            return false;
        }});
        let blur = false;
        const popupSettings = new Proxy(component('popup'), {get: (object, key) => {
            if (key === 'BLUR') return blur;
            if (key === 'NOTIFICATION') return notification;
            return object[key];
        }});
        const settings = new Proxy({}, {get: (_object, key) => {
            if (key === 'popup') return popupSettings;
            if (key.endsWith('_changed')) return () => {};
            return component(key);
        }});
        const extension = Object.create(ExtensionClass.prototype);
        extension._settings = settings;
        // Use the real reset(): it intentionally does nothing when disabled.
        // Stub only actor creation/destruction and the GLib event loop.
        const popup = Object.create(PopupClass.prototype);
        popup.settings = settings;
        popup.enabled = notification;
        popup.liveMenuBlur = false;
        popup.cancel_queued_blurs = () => {};
        popup.enable = function () {
            if (this.enabled) return;
            this.enabled = true;
            this.liveMenuBlur = blur;
        };
        popup.disable = function () { this.enabled = false; this.liveMenuBlur = false; };
        extension._popup = popup;
        extension._connect_to_settings();
        for (const value of [true, false, true, false]) {
            blur = value;
            callbacks['popup.BLUR_changed']();
            while (pending.length) pending.shift()();
            assert.equal(popup.liveMenuBlur, value, 'existing menu surfaces must follow their switch');
            assert.equal(popup.enabled, value || notification, 'notifications retain the shared component');
        }
    });
}
const Connections = load('src/conveniences/connections.js', 'Connections', {
    GObject: {Object: class {}},
});
for (const workspaceCount of [1, 2]) test(`application refresh releases old tracking (workspaces=${workspaceCount})`, () => {
    let nextId = 1;
    const handlers = new Map();
    const window = {
        connect: (signal, callback) => { const id = nextId++; handlers.set(id, {signal, callback}); return id; },
        disconnect: id => handlers.delete(id),
        get_compositor_private: () => null,
    };
    const Applications = load('src/components/applications.js', 'ApplicationsBlur', {
        PaintSignals: class {},
        global: {workspace_manager: {
            get_n_workspaces: () => workspaceCount,
            // A sticky window can appear in more than one workspace list.
            get_workspace_by_index: () => ({list_windows: () => [window]}),
        }},
    });
    const applications = new Applications(new Connections(), {applications: {}}, null);
    applications.check_blur = () => {}; // No rendering in this tracking-only test.
    applications.update_all_windows();
    assert.equal(applications.meta_window_map.size, 1, 'sticky windows must only be tracked once');
    const count = handlers.size;
    for (let i = 0; i < 20; i++) applications.update_all_windows();
    assert.equal(applications.meta_window_map.size, 1, 'refresh must release old window entries');
    assert.equal(handlers.size, count, 'refresh must release old Meta.Window signal handlers');
    for (const {signal, callback} of [...handlers.values()])
        if (signal === 'unmanaging') callback();
    assert.equal(applications.meta_window_map.size, 0, 'closing a window releases all tracking');
    assert.equal(handlers.size, 0, 'closing a window releases its signal handlers');
});
process.exitCode = failures ? 1 : 0;
