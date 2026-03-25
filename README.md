# VitalPro Reporting

VitalPro is now a Flutter reporting app backed by a small Node API. The API stores client branding, saved MSSQL servers, and saved report queries in MySQL, then runs selected read-only queries against one SQL Server at a time.

## What It Does

- Protects app launch with the daily password format `OneNetDDMMMyyyy`
- Protects the Admin panel with the same daily password format
- Saves client company name, address, and logo URL in MySQL
- Saves multiple MSSQL servers in MySQL
- Lets the user select one server at a time and store a local default server
- Saves reusable report queries in MySQL and shows them by `queryName`
- Runs read-only queries and shows table results
- Shows a chart preview when enabled and the result contains numeric data
- Prints or exports the report as PDF

## Backend Setup

1. Copy `.env.example` to `.env`
2. Update the MySQL and API host values
3. Install backend packages:

```bash
cd server
npm install
```

4. Start the API:

```bash
cd server
node server.js
```

## Flutter Setup

```bash
flutter pub get
flutter run
```

## Environment Settings

```env
API_BASE_URL=http://127.0.0.1:3000
HOST=0.0.0.0
PORT=3000
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=your_mysql_password
MYSQL_DATABASE=database_utilities
```

- Use `http://10.0.2.2:3000` for the Android emulator
- Use your Windows LAN IP for a real device

## Important Notes

- Admin password and launch password both use `OneNetDDMMMyyyy`
- Saved report queries are restricted to read-only `SELECT` or `WITH ... SELECT` statements
- SQL login servers are executed through the `mssql` driver
- Windows authentication servers are executed through `sqlcmd`, so `sqlcmd` must be installed and available in `PATH`
- Company logo is stored as a URL and is reused in the PDF header

## API Routes

- `GET /health`
- `GET /api/reporting/bootstrap`
- `POST /api/reporting/run`
- `POST /api/admin/verify`
- `POST /api/admin/bootstrap`
- `POST /api/admin/settings`
- `POST /api/admin/servers`
- `DELETE /api/admin/servers/:id`
- `POST /api/admin/queries`
- `DELETE /api/admin/queries/:id`
