# ![IWB Logo](https://iwbmedia.innerwebblueprint.com/2022/10/IWB-v2_5-triforce_IWB.png)

## 🧩 IWB Digital Presence Platform (IWB DPP)
> **The InnerWeb Blueprint to Self-Sovereign Web + Email Infrastructure**

---

### 🌐 What is IWB DPP?

The **IWB Digital Presence Platform** is a fully self-contained, self-hosted, and containerized web + email solution built for visionaries, creators, builders, and rebels who prefer autonomy over dependency.

It's **portable**, **persistent**, and **designed to run forever** — quietly powering your digital world in the background.

> _"Because your online presence should be yours—not rented."_  

---

### 🚀 Highlights

- 📦 **Single-container deployment** (Docker)
- 📫 **Self-hosted email** (Postfix + Dovecot + admin ui and webmail comming soon)
- 🌍 **High-performance WordPress** (Expertly Desgined by experince hosting MASSIVE sites)
- 🔐 **Persistent cloud backups** (via S3 compatible Storj)
- 🧠 **Smart defaults** with **manual overrides** when you need them
- ⚙️ **Works on bare metal, cloud VPS, or anywhere Docker runs**
- 💌 **Receives mail for every user at your domain** (You make your own accounts)
- 🕊️ **Freedom-friendly licensing** & designed for longevity

---

### 🛠️ How to Use

Start with the included example templates:

1. Copy `examples-templates/env.template` to `.env` and configure required fields
2. Copy `examples-templates/docker-compose.yml.template` to `docker-compose.yml`
3. Pull a prebuilt image: `docker pull iwbp/iwbdpp:latest` (or `:dev-latest` for development)
4. Start the platform: `docker-compose up -d`

**Required .env fields:**
- `COMPOSE_PROJECT_NAME` - Your 3-letter project code
- `IWB_DOMAIN` - Your domain name
- `IWB_MAIL_USER` & `IWB_MAIL_PASS` - Primary email credentials
- `IWB_STORJ_GRANT` - Storj cloud storage access grant

**Auto-generated (leave empty in .env):**
All database and service passwords are securely auto-generated on first startup and persisted to `/var/data/state/`. To view them later, run inside the container:
```bash
/var/setup/scripts/show-passwords.sh
```

> For full setup instructions, including environment variables, see the `docs/` folder _(coming soon)_.

---

### PHP request concurrency

The image requires PHP **8.3.36 or newer within the 8.3 branch**, including the
October 2026 emergency security fixes. Alpine selects the latest available patch
release during a fresh package installation. For security updates, rebuild with
`./scripts/build-and-push.sh --no-cache --skip-push`, then distribute the image and
recreate deployed containers. A restart alone does not update PHP. Verify each
replacement container with `php --version` and `php-fpm83 --version`.

The image ships a dynamic PHP-FPM pool with a maximum of **8 workers**, starting
with 2 and keeping 1–3 idle workers. Each worker handles one PHP request at a time;
when all are occupied, additional requests wait for a free worker.

The shared default lives in `includes/setup/configs/php/www.conf`. Rebuild the
image and recreate containers from that image to apply changes; restarting an
existing container does not install the new configuration.

Size this limit across every container on the host, leaving memory and CPU for
MariaDB, mail, n8n, and the operating system. TSP workers sampled around 180–210 MB
RSS on iwb002 in September 2026; this is an observation, not a per-worker ceiling,
and RSS includes shared memory. After rollout, check PHP-FPM's
`pm.max_children` warnings, request latency, host available memory, CPU load, and
swap activity during busy periods before increasing the limit further. Repeated
warnings can also indicate slow requests that need investigation.

---

### 📸 See it in Action
To understand the “why” behind the project, its purpose, and how it serves people and ideas (and see it in action), visit:
🌟 https://www.innerwebblueprint.com/about-iwb/

---

- [IWB Triforce Logo](https://iwbmedia.innerwebblueprint.com/2022/10/cropped-IWB-v2_5-triforce-logo_.png)
- [IWB Triforce + Text Logo](https://iwbmedia.innerwebblueprint.com/2022/10/IWB-v2_5-triforce_IWB.png)

---

### 💬 Want to Collaborate?
We believe in rising by lifting others.

If you’re building tech aligned with sovereignty, creative freedom, or new blueprints for digital infrastructure—reach out!

> _"We are not here to sell the web. We’re here to give it back."_ – InnerWeb Blueprint (IWB)

---

### 🏷️ Current Version

See the [VERSION](VERSION) file for current version. We follow [Semantic Versioning](https://semver.org/).

**Development workflow:** We use a changelog-driven commit workflow. See [CHANGELOG-GUIDE.md](CHANGELOG-GUIDE.md) for details.

**For developers:** Check [scripts/README.md](scripts/README.md) for automated build and deployment scripts.

---

#### ⚠️ Disclaimer

This project is actively evolving. While it’s already useful, it’s also an expression of something deeper. Contributions welcome. Opinions encouraged. Faith in the mission required. 🙏

---

