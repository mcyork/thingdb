# Upgrade Flag Protocol

## Overview
The upgrade flag system provides robust, boot-level recovery for inventory system updates. An independent recovery service monitors upgrade progress and automatically rolls back failed upgrades.

## Flag File Location
```
/var/lib/inventory/.upgrade-in-progress
```

## Flag Schema
```json
{
  "state": "upgrading|failed|completed",
  "upgrade_started": "2025-09-01T18:45:00Z",
  "previous_version": "1.0.0",
  "new_version": "1.1.0",
  "restarts_expected": 3,
  "restarts_completed": 0,
  "backup_location": "/var/lib/inventory/backups/v1.0.0",
  "rollback_safe": true,
  "package_signature": "sha256:abc123...",
  "upgrade_steps": [
    {
      "step": "backup",
      "status": "completed",
      "timestamp": "2025-09-01T18:45:10Z"
    },
    {
      "step": "extract",
      "status": "completed", 
      "timestamp": "2025-09-01T18:45:20Z"
    },
    {
      "step": "restart_service",
      "status": "in_progress",
      "timestamp": "2025-09-01T18:45:30Z"
    }
  ]
}
```

## State Definitions

### "upgrading"
- Upgrade is in progress
- Recovery service monitors restart counter
- If restarts_expected reaches 0, rollback is triggered

### "failed" 
- Upgrade has failed
- Recovery service will rollback immediately
- Flag is deleted after successful rollback

### "completed"
- Upgrade completed successfully
- Flag should be deleted
- Used for final validation before cleanup

## Restart Counter Logic

### During Upgrade:
1. Set `restarts_expected` based on planned restarts
2. Decrement counter after each service restart
3. Update `restarts_completed` count

### On Boot:
1. Recovery service decrements `restarts_expected` by 1
2. If `restarts_expected = 0` and `state = "upgrading"` → rollback
3. If `state = "failed"` → immediate rollback

## Recovery Service Behavior

### Boot Time:
- Check for flag file
- If exists and `state = "failed"` → rollback
- If exists and `restarts_expected = 0` and `state = "upgrading"` → rollback
- Otherwise, continue monitoring

### Runtime Monitoring:
- Check flag every 30 seconds
- Monitor for timeout conditions
- Handle rollback if needed

## Upgrade Steps Tracking

### Standard Steps:
- `backup`: Create backup of current version
- `extract`: Extract new package
- `install_deps`: Install new dependencies
- `restart_service`: Restart inventory-app service
- `validate`: Run health checks
- `cleanup`: Remove backup if successful

### Step Status:
- `pending`: Step not started
- `in_progress`: Step currently running
- `completed`: Step finished successfully
- `failed`: Step failed

## Rollback Safety

### `rollback_safe: true`
- Package is safe to rollback
- No database schema changes
- Code is backward compatible

### `rollback_safe: false`
- Package may not be safe to rollback
- Database migrations included
- User confirmation required for rollback

## Security

### Package Signature
- `package_signature`: SHA256 hash of package
- Validated against embedded certificates
- Ensures package authenticity

### Certificate Chain
- Root CA (TPM-secured)
- Intermediate CA (Mac-based)
- Package signatures verified against chain
