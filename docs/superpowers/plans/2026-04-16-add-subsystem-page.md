# Dedicated "Add Subsystem" Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the inline "Add Subsystem" form off the dashboard onto a dedicated `/ui/add` page with a worked example, helpful tips, and post-registration instructions.

**Architecture:** A new `GET /ui/add` route renders an `add_subsystem` template. The template has a two-column layout: form on the left, guidance on the right (collapses to single column on mobile). The form auto-fills fields from the service name. On success, it redirects to the service detail page. The dashboard's inline form is replaced with a simple link card. No backend changes — the existing `POST /services/create` endpoint is reused as-is.

**Tech Stack:** Perl 5.42, Mojolicious::Lite, vanilla JS. No new dependencies.

---

## File Structure

**Modified files:**
- `bin/321.pl` — all changes are here:
  - New route: `GET /ui/add` (around line 497, after `/ui/service/#name`)
  - New template: `@@ add_subsystem.html.ep` (in `__DATA__` section)
  - Modified template: dashboard's `loadServices()` JS — replace inline form with link card (lines 2061–2071)
  - Modified template: dashboard's `addSubsystem()` JS — remove entirely (lines 2074–2110)
  - New CSS in ops layout `<style>` block

**Untouched:**
- `POST /services/create` endpoint — no changes
- `lib/Deploy/Config.pm`, `lib/Deploy/Service.pm` — untouched
- All existing test files — untouched

---

## Task 1: Add the `/ui/add` route

**Files:**
- Modify: `bin/321.pl:497` (after the `/ui/service/#name` route)

- [ ] **Step 1: Add the route**

In `bin/321.pl`, after the `get '/ui/service/#name'` handler (line 496, after its closing `};`), add:

```perl
get '/ui/add' => sub ($c) {
    $c->render('add_subsystem');
};
```

- [ ] **Step 2: Verify the app still starts**

```bash
prove -lr t 2>&1 | tail -3
```
Expected: all tests pass (the template doesn't exist yet, but the route only renders on request).

- [ ] **Step 3: Commit and push**

```bash
git add bin/321.pl
git commit -m "Add GET /ui/add route for dedicated Add Subsystem page"
git push
```

---

## Task 2: Create the `add_subsystem` template

**Files:**
- Modify: `bin/321.pl` — append new template in the `__DATA__` section, before `app->start` or at the end of templates

The template goes after the last existing template in the `__DATA__` section. Find the end of the file and add the new template above nothing — it's appended to the `__DATA__` block.

- [ ] **Step 1: Find where to insert**

The `__DATA__` section starts at line 507. Templates are separated by `@@ name.html.ep` markers. Find the last template marker to know where to append. The new template goes at the very end of the file.

- [ ] **Step 2: Add the template**

Append to the very end of `bin/321.pl`:

```html
@@ add_subsystem.html.ep
% layout 'ops';
% title 'Add Subsystem';

<div class="page-header">
    <div class="page-title"><a href="/" class="back-link">&larr;</a> Add Subsystem</div>
</div>

<div class="add-page-grid">
    <div class="add-page-form">
        <div class="detail-info">
            <h2 class="add-section-title">Register a new service</h2>

            <div class="config-row">
                <span class="config-label">NAME</span>
                <input class="config-input" id="add-name" placeholder="pizza.web" autocomplete="off">
            </div>
            <div class="add-field-hint">Format: <code>group.service</code> &mdash; e.g. pizza.web, blog.api</div>

            <div class="config-row">
                <span class="config-label">REPO</span>
                <input class="config-input" id="add-repo" placeholder="/home/s3/web.pizza.do" autocomplete="off">
            </div>
            <div class="add-field-hint">Where the code lives (or will live after clone)</div>

            <div class="config-row">
                <span class="config-label">BRANCH</span>
                <input class="config-input" id="add-branch" value="master" autocomplete="off">
            </div>

            <h3 class="add-target-title">Dev target</h3>
            <div class="add-target-row">
                <div class="config-row">
                    <span class="config-label">HOST</span>
                    <input class="config-input" id="add-dev-host" placeholder="pizza.do.dev" autocomplete="off">
                </div>
                <div class="config-row">
                    <span class="config-label">PORT</span>
                    <input class="config-input" id="add-dev-port" placeholder="9500" autocomplete="off">
                </div>
            </div>

            <h3 class="add-target-title">Live target</h3>
            <div class="add-target-row">
                <div class="config-row">
                    <span class="config-label">HOST</span>
                    <input class="config-input" id="add-live-host" placeholder="pizza.do" autocomplete="off">
                </div>
                <div class="config-row">
                    <span class="config-label">PORT</span>
                    <input class="config-input" id="add-live-port" placeholder="9500" autocomplete="off">
                </div>
            </div>

            <div style="padding-top:16px">
                <button class="btn btn-deploy" id="create-btn" onclick="createSubsystem()" style="width:100%;justify-content:center">
                    CREATE
                </button>
            </div>
            <div id="create-error" class="add-error" style="display:none"></div>
        </div>
    </div>

    <div class="add-page-guide">
        <div class="detail-info">
            <h2 class="add-section-title">Example</h2>
            <div class="add-example">
                <div class="add-example-row"><span class="add-ex-label">NAME</span> <span class="add-ex-value">pizza.web</span></div>
                <div class="add-example-row"><span class="add-ex-label">REPO</span> <span class="add-ex-value">/home/s3/web.pizza.do</span></div>
                <div class="add-example-row"><span class="add-ex-label">BRANCH</span> <span class="add-ex-value">master</span></div>
                <div class="add-example-row"><span class="add-ex-label">DEV</span> <span class="add-ex-value">pizza.do.dev :9500</span></div>
                <div class="add-example-row"><span class="add-ex-label">LIVE</span> <span class="add-ex-value">pizza.do :9500</span></div>
            </div>
            <p class="add-guide-text">
                The <strong>name</strong> is <code>group.service</code> &mdash; the group drives the ubic service tree, the repo directory name, and the nginx config.
                The <strong>repo</strong> is where the code lives on disk. Convention is <code>/home/s3/web.&lt;group&gt;.do</code> for web services.
                <strong>Dev host</strong> gets a <code>.dev</code> suffix; mkcert handles local SSL. Pick an <strong>unused port</strong> &mdash; check the dashboard for what&rsquo;s taken.
            </p>

            <h2 class="add-section-title" style="margin-top:24px">What&rsquo;s next?</h2>
            <ol class="add-steps">
                <li>
                    <strong>Prepare the repo</strong> &mdash; make sure it exists and contains a <code>.321.yml</code> manifest at the root. Minimum:
                    <pre class="add-code">name: pizza.web
entry: bin/app.pl
runner: hypnotoad</pre>
                </li>
                <li>
                    <strong>Install the service</strong> &mdash; from the 321.do machine:
                    <pre class="add-code">321 install pizza.web</pre>
                    This clones the repo (if needed), installs Perl deps, sets up ubic + nginx + SSL, and starts the service.
                </li>
                <li>
                    <strong>Set secrets</strong> &mdash; if the manifest declares <code>env_required</code>, set them from the service detail page before deploying.
                </li>
                <li>
                    <strong>Check the dashboard</strong> &mdash; the service should appear with a green status LED.
                </li>
            </ol>

            <h2 class="add-section-title" style="margin-top:24px">Tips</h2>
            <ul class="add-tips">
                <li><strong>Ports</strong> &mdash; check the dashboard for ports already in use before picking one.</li>
                <li><strong>Naming</strong> &mdash; keep the group name short and lowercase. It&rsquo;s reused everywhere: ubic tree, repo dir, nginx config.</li>
                <li><strong>Dev parity</strong> &mdash; dev targets get the same nginx + SSL setup as live via mkcert. Run <code>321 hosts</code> after install to update <code>/etc/hosts</code>.</li>
                <li><strong>Branch</strong> &mdash; most services use <code>master</code>. Use <code>main</code> if that&rsquo;s what the repo uses.</li>
                <li><strong>No bin/runner field?</strong> &mdash; those come from the <code>.321.yml</code> manifest in the service repo, not from deploy config.</li>
            </ul>
        </div>
    </div>
</div>

%= content_for 'scripts' => begin
<script>
const nameInput = document.getElementById('add-name');
const repoInput = document.getElementById('add-repo');
const devHostInput = document.getElementById('add-dev-host');
const liveHostInput = document.getElementById('add-live-host');
const devPortInput = document.getElementById('add-dev-port');
const livePortInput = document.getElementById('add-live-port');

nameInput.addEventListener('input', function() {
    const name = this.value.trim();
    const group = name.split('.')[0];
    if (group && !repoInput.dataset.touched) {
        repoInput.value = '/home/s3/web.' + group + '.do';
    }
    if (group && !devHostInput.dataset.touched) {
        devHostInput.value = group + '.do.dev';
    }
    if (group && !liveHostInput.dataset.touched) {
        liveHostInput.value = group + '.do';
    }
});

devPortInput.addEventListener('input', function() {
    if (!livePortInput.dataset.touched) {
        livePortInput.value = this.value;
    }
});

[repoInput, devHostInput, liveHostInput, livePortInput].forEach(el => {
    el.addEventListener('input', function() { this.dataset.touched = '1'; });
});

async function createSubsystem() {
    const errEl = document.getElementById('create-error');
    errEl.style.display = 'none';

    const name = nameInput.value.trim();
    if (!name) { showError('Enter a service name'); return; }
    if (!/^[a-z0-9]+\.[a-z0-9]+$/.test(name)) {
        showError('Name must be group.service (e.g. pizza.web)');
        return;
    }

    const repo = repoInput.value.trim();
    if (!repo) { showError('Enter a repo path'); return; }

    const branch = document.getElementById('add-branch').value.trim() || 'master';
    const devHost = devHostInput.value.trim();
    const devPort = devPortInput.value.trim();
    const liveHost = liveHostInput.value.trim();
    const livePort = livePortInput.value.trim();

    if (!devPort && !livePort) { showError('Enter at least one port'); return; }

    const data = {
        name: name,
        repo: repo,
        branch: branch,
        targets: {},
    };

    if (devPort) {
        data.targets.dev = {
            host: devHost || 'localhost',
            port: parseInt(devPort, 10),
            runner: 'morbo',
            env: {},
            logs: {},
        };
    }
    if (livePort) {
        data.targets.live = {
            host: liveHost || 'localhost',
            port: parseInt(livePort, 10),
            runner: 'hypnotoad',
            env: {},
            logs: {},
        };
    }

    const btn = document.getElementById('create-btn');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> CREATING...';

    try {
        const d = await api('/services/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
        });
        if (d.status === 'success') {
            window.location.href = '/ui/service/' + name;
        } else {
            showError(d.message || 'Create failed');
        }
    } catch(e) {
        showError('Error: ' + e.message);
    }

    btn.disabled = false;
    btn.textContent = 'CREATE';
}

function showError(msg) {
    const el = document.getElementById('create-error');
    el.textContent = msg;
    el.style.display = 'block';
}
</script>
% end
```

- [ ] **Step 3: Verify the template renders**

```bash
prove -lr t 2>&1 | tail -3
```
Expected: all tests pass.

Then manually test:
```bash
curl -sS -u 321:kaizen http://127.0.0.1:9321/ui/add | grep -c 'add-page-grid'
```
Expected: `1` (the page renders with the grid).

- [ ] **Step 4: Commit and push**

```bash
git add bin/321.pl
git commit -m "Add dedicated Add Subsystem page with example and tips"
git push
```

---

## Task 3: Add CSS for the Add Subsystem page

**Files:**
- Modify: `bin/321.pl` — CSS in the ops layout `<style>` block

- [ ] **Step 1: Add CSS rules**

In `bin/321.pl`, find the `.add-subsystem-form` CSS block (line 1625). Replace the entire block from `.add-subsystem-form` through `.add-subsystem-btn:hover` (lines 1625–1663) with:

```css
.add-subsystem-form {
    background: var(--panel);
    border: 1px dashed var(--border-hi);
    padding: 20px;
}

.add-form-title {
    font-family: var(--display);
    font-size: 17px;
    font-weight: 700;
    letter-spacing: 3px;
    color: var(--text-2);
    margin-bottom: 16px;
}

.add-subsystem-btn {
    font-family: var(--display);
    font-weight: 700;
    font-size: 18px;
    letter-spacing: 3px;
    padding: 12px 24px;
    background: transparent;
    border: 1px dashed var(--border-hi);
    color: var(--text-2);
    cursor: pointer;
    transition: all 0.3s;
    width: 100%;
    min-height: 100px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    text-decoration: none;
}

.add-subsystem-btn:hover {
    border-color: var(--phosphor-dim);
    color: var(--phosphor);
    background: rgba(0, 255, 65, 0.03);
}

.add-page-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 24px;
    align-items: start;
}

.add-section-title {
    font-family: var(--display);
    font-size: 14px;
    font-weight: 700;
    letter-spacing: 2px;
    color: var(--phosphor);
    text-shadow: 0 0 8px var(--phosphor-glow);
    margin: 0 0 16px;
}

.add-target-title {
    font-family: var(--display);
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 2px;
    color: var(--text-2);
    margin: 16px 0 8px;
}

.add-target-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
}

.add-target-row .config-row {
    grid-template-columns: 60px 1fr;
}

.add-field-hint {
    font-size: 11px;
    color: var(--text-2);
    margin: -4px 0 12px 128px;
    opacity: 0.7;
}

.add-error {
    margin-top: 12px;
    padding: 8px 12px;
    background: rgba(204, 51, 51, 0.1);
    border: 1px solid #c33;
    color: #c33;
    font-size: 12px;
}

.add-example {
    background: var(--panel-2);
    border: 1px solid var(--border);
    padding: 12px 16px;
    margin-bottom: 16px;
    font-family: var(--mono);
    font-size: 13px;
}

.add-example-row {
    display: flex;
    gap: 12px;
    padding: 2px 0;
}

.add-ex-label {
    color: var(--text-2);
    min-width: 60px;
    font-size: 10px;
    letter-spacing: 1px;
    padding-top: 2px;
}

.add-ex-value {
    color: var(--phosphor-mid);
}

.add-guide-text {
    font-size: 13px;
    line-height: 1.6;
    color: var(--fg);
    opacity: 0.8;
}

.add-guide-text code {
    background: var(--panel-2);
    padding: 1px 4px;
    font-size: 12px;
}

.add-steps {
    font-size: 13px;
    line-height: 1.6;
    color: var(--fg);
    opacity: 0.8;
    padding-left: 20px;
}

.add-steps li {
    margin-bottom: 12px;
}

.add-code {
    background: var(--panel-2);
    border: 1px solid var(--border);
    padding: 8px 12px;
    margin: 6px 0;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--phosphor-mid);
    overflow-x: auto;
}

.add-tips {
    font-size: 13px;
    line-height: 1.6;
    color: var(--fg);
    opacity: 0.8;
    padding-left: 20px;
}

.add-tips li {
    margin-bottom: 8px;
}

.add-tips code {
    background: var(--panel-2);
    padding: 1px 4px;
    font-size: 12px;
}
```

Also add a responsive breakpoint. Find the existing media query at line 1766 (`@media (max-width: 900px)`) and add inside it, after the `.detail-grid` rule:

```css
    .add-page-grid { grid-template-columns: 1fr; }
    .add-target-row { grid-template-columns: 1fr; }
    .add-field-hint { margin-left: 0; }
```

- [ ] **Step 2: Run full suite**

```bash
prove -lr t 2>&1 | tail -3
```
Expected: all tests pass.

- [ ] **Step 3: Commit and push**

```bash
git add bin/321.pl
git commit -m "Add CSS for Add Subsystem page layout and guide styling"
git push
```

---

## Task 4: Replace dashboard inline form with link card

**Files:**
- Modify: `bin/321.pl` — dashboard template JS (`loadServices()` and `addSubsystem()`)

- [ ] **Step 1: Replace the inline form card with a link**

In `bin/321.pl`, find the "Add SUBSYSTEM card" block in `loadServices()` (lines 2061–2071). Replace:

```javascript
    // Add "ADD SUBSYSTEM" card
    const addCard = document.createElement('div');
    addCard.innerHTML = `<div class="add-subsystem-form" id="add-form">
        <div class="add-form-title">+ ADD SUBSYSTEM</div>
        <div class="config-row"><span class="config-label">NAME</span><input class="config-input" id="add-name" placeholder="myapp.web"></div>
        <div class="config-row"><span class="config-label">REPO</span><input class="config-input" id="add-repo" placeholder="/home/s3/myapp"></div>
        <div class="config-row"><span class="config-label">BIN</span><input class="config-input" id="add-bin" value="bin/app.pl"></div>
        <div class="config-row"><span class="config-label">PORT</span><input class="config-input" id="add-port" placeholder="8080"></div>
        <div style="padding-top:8px"><button class="btn btn-deploy" onclick="addSubsystem()" style="width:100%;justify-content:center">CREATE</button></div>
    </div>`;
    grid.appendChild(addCard);
```

With:

```javascript
    // Add "ADD SUBSYSTEM" link card
    const addCard = document.createElement('div');
    addCard.innerHTML = `<a href="/ui/add" class="add-subsystem-btn">+ ADD SUBSYSTEM</a>`;
    grid.appendChild(addCard);
```

- [ ] **Step 2: Remove the `addSubsystem()` function**

Delete the entire `addSubsystem()` function (lines 2074–2110 — from `async function addSubsystem()` through its closing `}`). This code is now in the dedicated page's template.

Also remove the guard in `loadServices()` that checks if `add-name` has a value. Find lines 2010–2012:

```javascript
    // Don't clobber the form if the user is typing in it
    const addName = document.getElementById('add-name');
    if (addName && addName.value.trim()) return;
```

Delete those three lines. The form no longer lives on the dashboard.

- [ ] **Step 3: Run full suite**

```bash
prove -lr t 2>&1 | tail -3
```
Expected: all tests pass.

- [ ] **Step 4: Smoke test in browser**

Restart the app:
```bash
bash -lc 'hypnotoad bin/321.pl'
```

Visit the dashboard. Confirm:
- The inline form is gone, replaced by a `+ ADD SUBSYSTEM` button card.
- Clicking it navigates to `/ui/add`.
- The Add Subsystem page renders with the form on the left and guide on the right.
- Typing a name auto-fills repo, dev host, live host.
- Typing a dev port auto-fills live port.
- Creating a service redirects to `/ui/service/<name>`.

- [ ] **Step 5: Commit and push**

```bash
git add bin/321.pl
git commit -m "Replace dashboard inline form with link to /ui/add"
git push
```

---

## Self-Review Checklist

- [x] Spec: `/ui/add` page with two-column layout — Task 2 (template) + Task 3 (CSS)
- [x] Spec: Form fields (name, repo, branch, dev host/port, live host/port) — Task 2
- [x] Spec: No bin/runner fields (manifest handles those) — Task 2 (not in form)
- [x] Spec: Auto-fill from name — Task 2 (JS event listeners)
- [x] Spec: Worked example — Task 2 (right column)
- [x] Spec: "What's next?" steps — Task 2 (numbered list with code blocks)
- [x] Spec: Tips section — Task 2 (bullet list)
- [x] Spec: Redirect to service detail on success — Task 2 (`window.location.href`)
- [x] Spec: Dashboard inline form replaced with link card — Task 4
- [x] Spec: `POST /services/create` unchanged — no backend tasks
- [x] No placeholders — all code shown in full
- [x] Naming consistent: `createSubsystem` (new page), `addSubsystem` removed from dashboard, `add-subsystem-btn` class reused
- [x] CSS variable names match existing codebase (`--panel`, `--border-hi`, `--phosphor`, `--text-2`, `--display`, `--mono`)
