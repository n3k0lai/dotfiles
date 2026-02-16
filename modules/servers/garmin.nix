# Garmin data backup service
# my 2fa is blocking us from authenticating. we need to swap to oauth2 instead.
{ config, lib, pkgs, ... }:

let
  garminScript = pkgs.writeScriptBin "garmin-backup.py" ''
#!${pkgs.python3.withPackages (ps: with ps; [ garminconnect google-api-python-client google-auth-oauthlib ])}/bin/python3
import os
import json
import sys
import time
from datetime import datetime, date, timedelta
from pathlib import Path
from garminconnect import Garmin
from googleapiclient.discovery import build
from googleapiclient.http import MediaInMemoryUpload
from google.oauth2.credentials import Credentials

# Configuration
HISTORICAL_START_DATE = date(2020, 1, 1)  # Adjust this to your Garmin account start
STATE_FILE = Path("/var/lib/garmin-backup/state.json")
MAX_DATES_PER_RUN = 90  # Process 90 days at a time to avoid rate limits
REQUEST_DELAY = 0.5  # 500ms delay between API calls

# Load secrets
with open("${config.age.secrets.garmin_email.path}", "r") as f:
    garmin_email = f.read().strip()
with open("${config.age.secrets.garmin_password.path}", "r") as f:
    garmin_password = f.read().strip()
gdrive_credentials_path = "${config.age.secrets.gdrive_credentials.path}"
gdrive_token_path = "${config.age.secrets.gdrive_token.path}"

def log(message):
    print(f"[{datetime.now().isoformat()}] {message}", flush=True)

def load_state():
    """Load last sync state or initialize for historical sync"""
    if STATE_FILE.exists():
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    
    # Initialize for full historical backup
    return {
        "last_daily_sync": HISTORICAL_START_DATE.isoformat(),
        "last_activity_sync": (datetime.now() - timedelta(days=365*5)).isoformat(),
        "synced_activities": [],
        "historical_complete": False,
        "failed_dates": []
    }

def save_state(state):
    """Save current sync state"""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def get_or_create_folder(service, name, parent_id=None):
    """Get folder ID or create if doesn't exist"""
    query = f"name='{name}' and mimeType='application/vnd.google-apps.folder' and trashed=false"
    if parent_id:
        query += f" and '{parent_id}' in parents"
    
    results = service.files().list(q=query, fields="files(id, name)").execute()
    if results.get("files"):
        return results["files"][0]["id"]
    
    metadata = {
        "name": name,
        "mimeType": "application/vnd.google-apps.folder"
    }
    if parent_id:
        metadata["parents"] = [parent_id]
    
    folder = service.files().create(body=metadata, fields="id").execute()
    return folder.get("id")

def file_exists(service, filename, parent_id):
    """Check if file exists in folder"""
    query = f"name='{filename}' and '{parent_id}' in parents and trashed=false"
    results = service.files().list(q=query, fields="files(id)").execute()
    return bool(results.get("files"))

def upload_json(service, data, filename, parent_id):
    """Upload JSON data to Google Drive"""
    if file_exists(service, filename, parent_id):
        return False
    
    file_metadata = {"name": filename, "parents": [parent_id]}
    media = MediaInMemoryUpload(
        json.dumps(data, indent=2).encode('utf-8'),
        mimetype='application/json',
        resumable=True
    )
    service.files().create(body=file_metadata, media_body=media, fields="id").execute()
    return True

def upload_or_update_markdown(service, content, filename, parent_id):
    """Upload or update markdown file"""
    query = f"name='{filename}' and '{parent_id}' in parents and trashed=false"
    results = service.files().list(q=query, fields="files(id)").execute()
    
    media = MediaInMemoryUpload(
        content.encode('utf-8'),
        mimetype='text/markdown',
        resumable=True
    )
    
    if results.get("files"):
        file_id = results["files"][0]["id"]
        service.files().update(fileId=file_id, media_body=media).execute()
    else:
        file_metadata = {"name": filename, "parents": [parent_id]}
        service.files().create(body=file_metadata, media_body=media, fields="id").execute()

try:
    log("Starting Garmin backup...")
    state = load_state()
    
    # Login to Garmin
    log("Logging into Garmin...")
    client = Garmin(garmin_email, garmin_password)
    client.login()
    log("Garmin login successful")

    # Authenticate Google Drive
    log("Authenticating with Google Drive...")
    creds = Credentials.from_authorized_user_file(
        gdrive_token_path,
        ["https://www.googleapis.com/auth/drive.file"]
    )
    service = build("drive", "v3", credentials=creds)

    # Setup folder structure
    main_folder_id = get_or_create_folder(service, "Garmin Data")
    activities_folder_id = get_or_create_folder(service, "Activities", main_folder_id)
    stats_folder_id = get_or_create_folder(service, "Stats", main_folder_id)
    hr_folder_id = get_or_create_folder(service, "HeartRates", main_folder_id)
    sleep_folder_id = get_or_create_folder(service, "Sleep", main_folder_id)
    summary_folder_id = get_or_create_folder(service, "Summaries", main_folder_id)

    # Sync activities (all historical activities)
    log("Fetching activities...")
    activities_uploaded = 0
    try:
        synced_ids = set(state.get("synced_activities", []))
        
        # Fetch in batches to handle large activity counts
        offset = 0
        batch_size = 100
        total_fetched = 0
        
        while True:
            activities = client.get_activities(offset, batch_size)
            if not activities:
                break
            
            total_fetched += len(activities)
            log(f"Processing activities batch: {total_fetched} total fetched")
            
            for activity in activities:
                activity_id = activity.get("activityId")
                if not activity_id or activity_id in synced_ids:
                    continue
                
                filename = f"activity_{activity_id}.json"
                if upload_json(service, activity, filename, activities_folder_id):
                    activities_uploaded += 1
                    synced_ids.add(activity_id)
                    if activities_uploaded % 10 == 0:
                        log(f"Uploaded {activities_uploaded} activities...")
                
                time.sleep(REQUEST_DELAY)  # Rate limiting
            
            # If we got fewer than batch_size, we've reached the end
            if len(activities) < batch_size:
                break
            
            offset += batch_size
            time.sleep(REQUEST_DELAY * 2)  # Extra delay between batches
        
        state["synced_activities"] = list(synced_ids)
        state["last_activity_sync"] = datetime.now().isoformat()
        log(f"Activity sync complete: {activities_uploaded} new activities uploaded")
    except Exception as e:
        log(f"Error syncing activities: {e}")
        import traceback
        traceback.print_exc()

    # Sync daily stats (chunked historical sync)
    last_sync_date = date.fromisoformat(state["last_daily_sync"])
    today = date.today()
    
    # Calculate end date for this run (process MAX_DATES_PER_RUN at a time)
    end_date = min(last_sync_date + timedelta(days=MAX_DATES_PER_RUN), today)
    
    log(f"Syncing daily data from {last_sync_date} to {end_date}")
    log(f"Historical complete: {state.get('historical_complete', False)}")
    
    current_date = last_sync_date
    stats_uploaded = 0
    hr_uploaded = 0
    sleep_uploaded = 0
    failed_dates = state.get("failed_dates", [])
    markdown_entries = []
    
    while current_date <= end_date:
        date_str = current_date.strftime('%Y-%m-%d')
        
        try:
            # Fetch stats
            stats = client.get_stats(date_str)
            filename = f"stats_{date_str}.json"
            if upload_json(service, stats, filename, stats_folder_id):
                stats_uploaded += 1
            time.sleep(REQUEST_DELAY)
            
            # Fetch heart rate data
            try:
                hr_data = client.get_heart_rates(date_str)
                filename = f"hr_{date_str}.json"
                if upload_json(service, hr_data, filename, hr_folder_id):
                    hr_uploaded += 1
                time.sleep(REQUEST_DELAY)
            except Exception as e:
                log(f"No HR data for {date_str}: {e}")
            
            # Fetch sleep data
            try:
                sleep_data = client.get_sleep_data(date_str)
                filename = f"sleep_{date_str}.json"
                if upload_json(service, sleep_data, filename, sleep_folder_id):
                    sleep_uploaded += 1
                time.sleep(REQUEST_DELAY)
            except Exception as e:
                log(f"No sleep data for {date_str}: {e}")
            
            # Build markdown entry
            steps = stats.get("totalSteps", "N/A")
            calories = stats.get("totalKilocalories", "N/A")
            distance = stats.get("totalDistanceMeters", 0) / 1000
            
            # Try to get weight/body composition
            weight_data = ""
            try:
                user_summary = client.get_user_summary(date_str)
                if user_summary:
                    weight = user_summary.get("weight")
                    body_fat = user_summary.get("bodyFat")
                    if weight:
                        weight_data = f"\nWeight: {weight/1000:.1f} kg"
                        if body_fat:
                            weight_data += f" | Body Fat: {body_fat:.1f}%"
                time.sleep(REQUEST_DELAY)
            except:
                pass
            
            # Get body battery if available
            body_battery = ""
            try:
                if hr_data and "bodyBatteryValuesArray" in hr_data:
                    bb_values = hr_data.get("bodyBatteryValuesArray", [])
                    if bb_values:
                        latest_bb = bb_values[-1]
                        body_battery = f"\nBody Battery: {latest_bb}"
            except:
                pass
            
            markdown_entries.append(f"""## {date_str}
Steps: {steps} | Calories: {calories} | Distance: {distance:.1f} km{weight_data}{body_battery}
""")
            
            if stats_uploaded % 10 == 0 and stats_uploaded > 0:
                log(f"Progress: {stats_uploaded} days synced...")
            
        except Exception as e:
            log(f"Error fetching data for {date_str}: {e}")
            if date_str not in failed_dates:
                failed_dates.append(date_str)
        
        current_date += timedelta(days=1)
    
    # Upload consolidated markdown summary (append to existing)
    if markdown_entries:
        # Try to fetch existing summary
        existing_content = ""
        query = f"name='garmin_summary.md' and '{summary_folder_id}' in parents and trashed=false"
        results = service.files().list(q=query, fields="files(id)").execute()
        if results.get("files"):
            file_id = results["files"][0]["id"]
            try:
                from googleapiclient.http import MediaIoBaseDownload
                import io
                request = service.files().get_media(fileId=file_id)
                fh = io.BytesIO()
                downloader = MediaIoBaseDownload(fh, request)
                done = False
                while not done:
                    status, done = downloader.next_chunk()
                existing_content = fh.getvalue().decode('utf-8')
            except:
                pass
        
        # Build new content
        header = f"# Garmin Data Summary\n\nLast updated: {datetime.now().isoformat()}\n\n"
        new_entries = "\n".join(markdown_entries)
        
        # If we have existing content, append to it (remove old header)
        if existing_content:
            # Remove old header and append new entries
            if "##" in existing_content:
                old_entries = existing_content[existing_content.find("##"):]
                markdown_content = header + new_entries + "\n\n" + old_entries
            else:
                markdown_content = header + new_entries
        else:
            markdown_content = header + new_entries
        
        upload_or_update_markdown(service, markdown_content, "garmin_summary.md", summary_folder_id)
        log("Updated markdown summary")
    
    # Update state
    state["last_daily_sync"] = end_date.isoformat()
    state["failed_dates"] = failed_dates
    
    # Check if historical sync is complete
    if end_date >= today:
        state["historical_complete"] = True
        log("Historical sync complete! Now in incremental mode.")
    else:
        days_remaining = (today - end_date).days
        log(f"Historical sync progress: {days_remaining} days remaining")
    
    save_state(state)
    
    log(f"Backup complete: {activities_uploaded} activities, {stats_uploaded} daily stats, {hr_uploaded} HR days, {sleep_uploaded} sleep days")
    if failed_dates:
        log(f"Failed dates: {len(failed_dates)}")

except Exception as e:
    log(f"Fatal error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
  '';
in
{
  systemd.services.garmin-backup = {
description = "Garmin Data Backup Service";

serviceConfig = {
  Type = "oneshot";
  ExecStart = "${garminScript}/bin/garmin-backup.py";
  User = "root";
  Group = "root";
  
  # Set HOME for garminconnect token storage
  Environment = "HOME=/var/lib/garmin-backup";
  
  # Create state directory
  StateDirectory = "garmin-backup";
  
  # Allow up to 4 hours for initial historical sync
  TimeoutStartSec = "4h";
  
  # Security hardening
  PrivateTmp = true;
  ProtectSystem = "strict";
  ProtectHome = true;
  ReadWritePaths = "/var/lib/garmin-backup";
};

wants = [ "network-online.target" ];
after = [ "network-online.target" ];
  };

  systemd.timers.garmin-backup = {
description = "Garmin Data Backup Timer";
wantedBy = [ "timers.target" ];

timerConfig = {
  # Run 5 minutes after boot, then every 6 hours after last completion
  OnBootSec = "5min";
  OnUnitActiveSec = "6h";
  Persistent = true;
};
  };
}