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

const FrameType = { NORMAL: 0, DIALOG: 1, MODAL_DIALOG: 2, UTILITY: 3, MENU: 4, ATTACHED: 5 };
const WindowRules = load('src/components/applications/window_rules.js', 'WindowRules',
    { Meta: { FrameType } });

function win(wm_class, { app_id = null, parent = null, frame = FrameType.NORMAL } = {}) {
    return {
        get_wm_class: () => wm_class,
        get_gtk_application_id: () => app_id,
        get_transient_for: () => parent,
        get_frame_type: () => frame,
    };
}
function rules(enable_all, whitelist, blacklist) {
    return new WindowRules({ applications: {
        ENABLE_ALL: enable_all, WHITELIST: whitelist, BLACKLIST: blacklist,
    } });
}

test('an attached dialog inherits its app through transient-for', () => {
    const app = win('org.gnome.TextEditor');
    const dialog = win('xdg-desktop-portal-gnome', { parent: app, frame: FrameType.ATTACHED });
    assert.equal(rules(false, ['org.gnome.TextEditor'], []).matches(dialog), true);
});

test('a utility palette is blurred like its app', () => {
    const app = win('gimp');
    const palette = win('gimp', { parent: app, frame: FrameType.UTILITY });
    assert.equal(rules(true, [], []).matches(palette), true);
});

test('the GTK application id matches when the wm_class does not', () => {
    const window = win('', { app_id: 'org.gnome.Nautilus' });
    assert.equal(rules(false, ['org.gnome.Nautilus'], []).matches(window), true);
});

test('the allow list wins over the block list in all mode', () => {
    const window = win('io.github.DevWebeloper.AuraGlassSettings');
    assert.equal(rules(true, ['io.github.DevWebeloper.AuraGlassSettings'], ['*aura*']).matches(window), true);
});

test('a blocked app stays unblurred, dialogs included', () => {
    const app = win('firefox');
    const dialog = win('firefox', { parent: app, frame: FrameType.ATTACHED });
    assert.equal(rules(true, [], ['*firefox*']).matches(dialog), false);
});

test('menus are never blurred', () => {
    assert.equal(rules(true, [], []).matches(win('org.gnome.Nautilus', { frame: FrameType.MENU })), false);
});

test('a transient-for loop ends', () => {
    const a = win('a'), b = win('b', { parent: a });
    a.get_transient_for = () => b;
    assert.equal(rules(false, ['b'], []).matches(a), true);
});

// full-size-buffers: the stock rules, then the kept-at-monitor-size ones.
const sizing = load('src/render/shader/texture_region.js',
    '({ set_full_size_buffers, textureFits, initialTextureCapacity, getTextureCapacity })');

test('stock sizing is exact, grows 1.25x, stops at the view and shrinks below half', () => {
    sizing.set_full_size_buffers(false);
    assert.equal(sizing.initialTextureCapacity(200, 3440), 200);
    assert.equal(sizing.getTextureCapacity(400, 300, 3440), 500);
});

test('full-size buffers start at the monitor and never shrink', () => {
    sizing.set_full_size_buffers(true);
    assert.equal(sizing.initialTextureCapacity(200, 3440), 3440);
    assert.equal(sizing.getTextureCapacity(400, 300, 3440), 3440);
    assert.equal(sizing.textureFits({}, 1, 1, 3440, 1440), true);
    assert.equal(sizing.textureFits({}, 3441, 1, 3440, 1440), false);
    assert.equal(sizing.initialTextureCapacity(4000, 3440), 4000);
    sizing.set_full_size_buffers(false);
});

if (failures)
    process.exit(1);
