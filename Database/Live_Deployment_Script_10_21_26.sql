-- =====================================================
-- IntegrationCredential Table Migration
-- Stores the Setup page's integration settings (Maconomy,
-- Microsoft Graph, SharePoint) that used to live in
-- appsettings.json. One row per (Provider, SettingKey).
--
-- No data is inserted here: the first time the API reads a
-- provider that has no rows, it imports that provider's
-- current appsettings.json values (see
-- IntegrationCredentialService). Secret values (passwords,
-- client secret) are written encrypted by the API, so they
-- must never be inserted by hand in plain text.
-- =====================================================
--0
BEGIN TRAN;
DELETE FROM dbo.JobMessageRead;
DELETE FROM dbo.JobMessage;
DELETE FROM dbo.JobActivityLog;
DELETE FROM dbo.Timesheet;
DELETE FROM dbo.JobDetails;
DELETE FROM dbo.Jobs;
DELETE FROM dbo.Client;
DELETE FROM dbo.[Partner];
DELETE FROM dbo.WipGeneration;
DELETE FROM dbo.NotificationDetails;
DELETE FROM dbo.Notifications;
DELETE FROM dbo.Notes;
DELETE FROM dbo.ActivityLog;
DELETE FROM dbo.[Log];
DELETE FROM dbo.QueuedEmail;
COMMIT;

--1
IF OBJECT_ID(N'[dbo].[IntegrationCredential]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[IntegrationCredential]
    (
        [Id] NVARCHAR(450) NOT NULL PRIMARY KEY DEFAULT (NEWID()),
        [Provider] NVARCHAR(50) NOT NULL,
        [SettingKey] NVARCHAR(100) NOT NULL,
        [SettingValue] NVARCHAR(MAX) NULL,
        [IsEncrypted] BIT NOT NULL DEFAULT 0,
        [CreatedOnUtc] DATETIME2(6) NOT NULL DEFAULT GETUTCDATE(),
        [UpdatedOnUtc] DATETIME2(6) NOT NULL DEFAULT GETUTCDATE(),
        [UpdatedByUserName] NVARCHAR(255) NULL
    );

    PRINT 'IntegrationCredential table created successfully.';
END
ELSE
BEGIN
    PRINT 'IntegrationCredential table already exists.';
END
GO

-- =====================================================
-- Verify (values never shown; columns common to every version of the table)
-- =====================================================
SELECT
    [Provider],
    [SettingKey],
    [UpdatedOnUtc]
FROM [dbo].[IntegrationCredential]
ORDER BY [Provider], [SettingKey];
GO


--2
-- =====================================================
-- IntegrationCredential Table Upgrade
-- Brings an IntegrationCredential table created by an earlier
-- draft of 005 (EncryptedValue / UpdatedByUserId columns) up to
-- the current shape. 005 skips tables that already exist, so
-- those databases fail with "Invalid column name 'SettingValue'"
-- etc. Safe to run repeatedly; does nothing on a table already
-- created by the current 005.
-- =====================================================

-- EncryptedValue -> SettingValue (now nullable)
IF COL_LENGTH('dbo.IntegrationCredential', 'EncryptedValue') IS NOT NULL
   AND COL_LENGTH('dbo.IntegrationCredential', 'SettingValue') IS NULL
BEGIN
    EXEC sp_rename 'dbo.IntegrationCredential.EncryptedValue', 'SettingValue', 'COLUMN';
    PRINT 'Renamed EncryptedValue to SettingValue.';
END
GO

IF COL_LENGTH('dbo.IntegrationCredential', 'SettingValue') IS NOT NULL
    ALTER TABLE [dbo].[IntegrationCredential] ALTER COLUMN [SettingValue] NVARCHAR(MAX) NULL;
GO

-- IsSecret: rows from the old table were all stored encrypted, so they are flagged as secret
-- (007 renames it to IsEncrypted; skipped when the table already has IsEncrypted)
IF COL_LENGTH('dbo.IntegrationCredential', 'IsSecret') IS NULL
   AND COL_LENGTH('dbo.IntegrationCredential', 'IsEncrypted') IS NULL
BEGIN
    ALTER TABLE [dbo].[IntegrationCredential]
        ADD [IsSecret] BIT NOT NULL CONSTRAINT [DF_IntegrationCredential_IsSecret] DEFAULT 0;
    PRINT 'Added IsSecret.';

    EXEC('UPDATE [dbo].[IntegrationCredential] SET [IsSecret] = 1');
END
GO

IF COL_LENGTH('dbo.IntegrationCredential', 'CreatedOnUtc') IS NULL
BEGIN
    ALTER TABLE [dbo].[IntegrationCredential]
        ADD [CreatedOnUtc] DATETIME2(6) NOT NULL CONSTRAINT [DF_IntegrationCredential_CreatedOnUtc] DEFAULT GETUTCDATE();
    PRINT 'Added CreatedOnUtc.';
END
GO

-- UpdatedByUserId -> UpdatedByUserName (old values were ids, not names, so they are dropped)
IF COL_LENGTH('dbo.IntegrationCredential', 'UpdatedByUserName') IS NULL
BEGIN
    ALTER TABLE [dbo].[IntegrationCredential] ADD [UpdatedByUserName] NVARCHAR(255) NULL;
    PRINT 'Added UpdatedByUserName.';
END
GO

IF COL_LENGTH('dbo.IntegrationCredential', 'UpdatedByUserId') IS NOT NULL
BEGIN
    ALTER TABLE [dbo].[IntegrationCredential] DROP COLUMN [UpdatedByUserId];
    PRINT 'Dropped UpdatedByUserId.';
END
GO


-- =====================================================
-- Verify
-- =====================================================
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'IntegrationCredential'
ORDER BY ORDINAL_POSITION;
GO


--3

-- =====================================================
-- IntegrationCredential: IsSecret -> IsEncrypted
-- Every setting value is now stored encrypted (not only
-- passwords / client secrets), so the flag means "SettingValue
-- is a Data Protection payload". Rows still holding plain
-- values (IsEncrypted = 0) are encrypted by the API the next
-- time it reads them (see IntegrationCredentialService) -
-- encryption can't be done here because the keys live in the
-- API's Data Protection key ring.
-- Safe to run repeatedly.
-- =====================================================

IF COL_LENGTH('dbo.IntegrationCredential', 'IsSecret') IS NOT NULL
   AND COL_LENGTH('dbo.IntegrationCredential', 'IsEncrypted') IS NULL
BEGIN
    EXEC sp_rename 'dbo.IntegrationCredential.IsSecret', 'IsEncrypted', 'COLUMN';
    PRINT 'Renamed IsSecret to IsEncrypted.';
END
GO

-- =====================================================
-- Verify (values never shown)
-- =====================================================
SELECT
    [Provider],
    [SettingKey],
    [IsEncrypted],
    [UpdatedOnUtc],
    [UpdatedByUserName]
FROM [dbo].[IntegrationCredential]
ORDER BY [Provider], [SettingKey];
GO


--4

-- Schema for the Role & Permission module (View / Manage per menu).
--
-- These tables already exist in databases created from the original template (they match
-- WIPBilling_Test exactly), but no script in this folder created them. This script makes a
-- database built from the repo scripts complete. Every step is guarded, so it is safe to run
-- on a database that already has some or all of them - nothing is altered or dropped.
--
-- Run order:
--   1. create_role_permissions_tables.sql   (this file - tables / columns)
--   2. seed_role_permissions.sql            (modules, menus, company switches, Partner defaults)
--
-- Tables:
--   Modules          - groups of pages (e.g. "WIP Billing", "Administration")
--   Menus            - one row per page; MenuName is the key the code checks (e.g. "M-wip-review")
--   CompanyModules   - which modules are switched on for each company
--   MenuPermissions  - a role's View / Manage on a menu
-- Column:
--   AspNetUsers.PartnerNumber - links a Partner-role login to its partner record (Add / Edit User form)
--
-- Run manually against the target database; there is no migrations tool wired up in this project.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- 0. AspNetRoles custom columns ----------------------------------------------
-- ApplicationRole.cs maps these, and permission checks read IsPrimaryRole on every request.
-- schema_identity.sql / schema_identity_custom.sql never add them, so add any that are missing
-- (nullable, matching existing databases; seed_role_permissions.sql backfills the NULLs).

IF COL_LENGTH(N'dbo.AspNetRoles', N'CompanyId') IS NULL
    ALTER TABLE [dbo].[AspNetRoles] ADD [CompanyId] NVARCHAR(450) NULL;
IF COL_LENGTH(N'dbo.AspNetRoles', N'IsPrimaryRole') IS NULL
    ALTER TABLE [dbo].[AspNetRoles] ADD [IsPrimaryRole] BIT NULL;
IF COL_LENGTH(N'dbo.AspNetRoles', N'CreatedOnUtc') IS NULL
    ALTER TABLE [dbo].[AspNetRoles] ADD [CreatedOnUtc] DATETIME2 NULL;
IF COL_LENGTH(N'dbo.AspNetRoles', N'CreatedById') IS NULL
    ALTER TABLE [dbo].[AspNetRoles] ADD [CreatedById] NVARCHAR(450) NULL;
IF COL_LENGTH(N'dbo.AspNetRoles', N'UpdatedOnUtc') IS NULL
    ALTER TABLE [dbo].[AspNetRoles] ADD [UpdatedOnUtc] DATETIME2 NULL;
IF COL_LENGTH(N'dbo.AspNetRoles', N'UpdatedById') IS NULL
    ALTER TABLE [dbo].[AspNetRoles] ADD [UpdatedById] NVARCHAR(450) NULL;
IF COL_LENGTH(N'dbo.AspNetRoles', N'Deleted') IS NULL
    ALTER TABLE [dbo].[AspNetRoles] ADD [Deleted] BIT NULL;
GO

-- 1. Modules -----------------------------------------------------------------

IF OBJECT_ID(N'[dbo].[Modules]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Modules]
    (
        [Id]            NVARCHAR(450)  NOT NULL,
        [Name]          NVARCHAR(128)  NULL,
        [Active]        BIT            NOT NULL CONSTRAINT DF_Modules_Active DEFAULT (0),
        [Sortorder]     INT            NOT NULL CONSTRAINT DF_Modules_Sortorder DEFAULT (0),
        [CreatedOnUtc]  DATETIME2(6)   NOT NULL,
        [CreatedById]   NVARCHAR(450)  NOT NULL,
        [UpdatedOnUtc]  DATETIME2(6)   NULL,
        [UpdatedById]   NVARCHAR(450)  NULL,
        [Deleted]       BIT            NOT NULL,
        CONSTRAINT PK_Modules PRIMARY KEY ([Id])
    );
    PRINT 'Created dbo.Modules';
END
GO

-- 2. Menus -------------------------------------------------------------------

IF OBJECT_ID(N'[dbo].[Menus]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Menus]
    (
        [Id]            NVARCHAR(450)  NOT NULL,
        [ModuleId]      NVARCHAR(450)  NULL,
        [MenuName]      NVARCHAR(128)  NOT NULL,
        [DisplayName]   NVARCHAR(128)  NOT NULL,
        [Sortorder]     INT            NOT NULL CONSTRAINT DF_Menus_Sortorder DEFAULT (0),
        [ParentMenuId]  NVARCHAR(450)  NULL,
        [Active]        BIT            NOT NULL CONSTRAINT DF_Menus_Active DEFAULT (0),
        [Link]          NVARCHAR(900)  NULL,
        [Icon]          NVARCHAR(128)  NULL,
        [CreatedOnUtc]  DATETIME2(6)   NOT NULL,
        [CreatedById]   NVARCHAR(450)  NOT NULL,
        [UpdatedOnUtc]  DATETIME2(6)   NULL,
        [UpdatedById]   NVARCHAR(450)  NULL,
        [Deleted]       BIT            NOT NULL,
        CONSTRAINT PK_Menus PRIMARY KEY ([Id])
    );
    PRINT 'Created dbo.Menus';
END
GO

-- 3. CompanyModules ----------------------------------------------------------

IF OBJECT_ID(N'[dbo].[CompanyModules]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[CompanyModules]
    (
        [Id]            NVARCHAR(450)  NOT NULL,
        [CompanyId]     NVARCHAR(450)  NOT NULL,
        [ModuleId]      NVARCHAR(450)  NOT NULL,
        [Active]        BIT            NOT NULL CONSTRAINT DF_CompanyModules_Active DEFAULT (0),
        [CreatedOnUtc]  DATETIME2(6)   NOT NULL,
        [CreatedById]   NVARCHAR(450)  NOT NULL,
        [UpdatedOnUtc]  DATETIME2(6)   NULL,
        [UpdatedById]   NVARCHAR(450)  NULL,
        [Deleted]       BIT            NOT NULL,
        CONSTRAINT PK_CompanyModules PRIMARY KEY ([Id])
    );
    PRINT 'Created dbo.CompanyModules';
END
GO

-- 4. MenuPermissions ---------------------------------------------------------

IF OBJECT_ID(N'[dbo].[MenuPermissions]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[MenuPermissions]
    (
        [Id]            NVARCHAR(450)  NOT NULL,
        [MenuId]        NVARCHAR(450)  NOT NULL,
        [RoleId]        NVARCHAR(450)  NOT NULL,
        [IsManage]      BIT            NOT NULL,
        [IsView]        BIT            NOT NULL,
        [CreatedOnUtc]  DATETIME2(6)   NOT NULL,
        [CreatedById]   NVARCHAR(450)  NOT NULL,
        [UpdatedOnUtc]  DATETIME2(6)   NULL,
        [UpdatedById]   NVARCHAR(450)  NULL,
        [Deleted]       BIT            NOT NULL,
        CONSTRAINT PK_MenuPermissions PRIMARY KEY ([Id])
    );
    PRINT 'Created dbo.MenuPermissions';
END
GO

-- a permission row always points at a real menu and role
-- (deleting a role removes its rows first - see RoleController.DeleteRole)
IF OBJECT_ID(N'[dbo].[FK_MenuPermissions_Menus]', 'F') IS NULL
BEGIN
    ALTER TABLE [dbo].[MenuPermissions] ADD CONSTRAINT FK_MenuPermissions_Menus
        FOREIGN KEY ([MenuId]) REFERENCES [dbo].[Menus] ([Id]);
    PRINT 'Added FK_MenuPermissions_Menus';
END
GO

IF OBJECT_ID(N'[dbo].[FK_MenuPermissions_AspNetRoles]', 'F') IS NULL
BEGIN
    ALTER TABLE [dbo].[MenuPermissions] ADD CONSTRAINT FK_MenuPermissions_AspNetRoles
        FOREIGN KEY ([RoleId]) REFERENCES [dbo].[AspNetRoles] ([Id]);
    PRINT 'Added FK_MenuPermissions_AspNetRoles';
END
GO

-- 5. AspNetUsers.PartnerNumber -----------------------------------------------

IF COL_LENGTH(N'dbo.AspNetUsers', N'PartnerNumber') IS NULL
BEGIN
    ALTER TABLE [dbo].[AspNetUsers] ADD [PartnerNumber] NVARCHAR(50) NULL;
    PRINT 'Added AspNetUsers.PartnerNumber';
END
GO

PRINT 'Role permission tables are in place.';
GO

--5

-- Seeds the Role & Permission module: Modules, Menus, the company module switches and the
-- default menu permissions for the Partner role.
--
-- How permissions work (see Vsky.Services/Permissions/PermissionService.cs):
--   - every page in the app is a row in dbo.Menus, grouped under a dbo.Modules row
--   - a role holds View and/or Manage on a menu in dbo.MenuPermissions (Manage includes View)
--   - a company only sees modules switched on for it in dbo.CompanyModules
--   - SuperAdmin and system roles (AspNetRoles.IsPrimaryRole = 1, e.g. Administrator) always have
--     full access and need no MenuPermissions rows
--
-- MenuName values are referenced in code (MenuNames in PermissionConstants.cs and the web app's
-- route "menu" meta) - do not rename them.
--
-- Safe to re-run: every insert is guarded, existing permissions are never overwritten.
-- Run manually against the target database; there is no migrations tool wired up in this project.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRANSACTION;

BEGIN TRY

    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    DECLARE @by NVARCHAR(450) = 'seed_role_permissions';

    -- 1. Modules -----------------------------------------------------------

    DECLARE @modWip   NVARCHAR(450) = 'B5C1A3E0-7D2F-4C61-9A4E-0F1D2C3B4A01';
    DECLARE @modAdmin NVARCHAR(450) = 'B5C1A3E0-7D2F-4C61-9A4E-0F1D2C3B4A02';

    IF NOT EXISTS (SELECT 1 FROM dbo.Modules WHERE Id = @modWip)
        INSERT INTO dbo.Modules (Id, Name, Sortorder, Active, CreatedOnUtc, CreatedById, Deleted)
        VALUES (@modWip, 'WIP Billing', 1, 1, @now, @by, 0);

    IF NOT EXISTS (SELECT 1 FROM dbo.Modules WHERE Id = @modAdmin)
        INSERT INTO dbo.Modules (Id, Name, Sortorder, Active, CreatedOnUtc, CreatedById, Deleted)
        VALUES (@modAdmin, 'Administration', 2, 1, @now, @by, 0);

    -- 2. Menus (one per page; Link = web route path, Icon = sidebar icon) ---

    DECLARE @menus TABLE (Id NVARCHAR(450), ModuleId NVARCHAR(450), MenuName NVARCHAR(128), DisplayName NVARCHAR(128), Sortorder INT, Link NVARCHAR(900), Icon NVARCHAR(100));

    INSERT INTO @menus VALUES
        ('C6D2B4F1-8E30-4D72-AB5F-1E2D3C4B5A01', @modWip,   'M-wip-sheet-generator', 'WIP Sheet Generator', 1, '/wipsheetgenerate',          'fa-solid fa-file-invoice'),
        ('C6D2B4F1-8E30-4D72-AB5F-1E2D3C4B5A02', @modWip,   'M-wip-review',          'WIP Review',          2, '/partner/wip-review',        'fa-solid fa-list-check'),
        ('C6D2B4F1-8E30-4D72-AB5F-1E2D3C4B5A03', @modAdmin, 'M-setup',               'Setup',               1, '/partner/wip-review/setup',  'fa-solid fa-gear'),
        ('C6D2B4F1-8E30-4D72-AB5F-1E2D3C4B5A04', @modAdmin, 'M-system-users',        'Users',               2, '/users',                     'fa-solid fa-users'),
        ('C6D2B4F1-8E30-4D72-AB5F-1E2D3C4B5A05', @modAdmin, 'M-roles',               'Roles & Permissions', 3, '/roles',                     'fa-solid fa-user-shield');

    INSERT INTO dbo.Menus (Id, ModuleId, MenuName, DisplayName, Sortorder, ParentMenuId, Active, Link, Icon, CreatedOnUtc, CreatedById, Deleted)
    SELECT m.Id, m.ModuleId, m.MenuName, m.DisplayName, m.Sortorder, NULL, 1, m.Link, m.Icon, @now, @by, 0
    FROM @menus m
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Menus x WHERE x.MenuName = m.MenuName AND x.Deleted = 0);

    -- 3. Switch both modules on for every company ---------------------------

    INSERT INTO dbo.CompanyModules (Id, CompanyId, ModuleId, Active, CreatedOnUtc, CreatedById, Deleted)
    SELECT CONVERT(NVARCHAR(36), NEWID()), c.Id, m.Id, 1, @now, @by, 0
    FROM dbo.Company c
    CROSS JOIN dbo.Modules m
    WHERE m.Id IN (@modWip, @modAdmin)
      AND NOT EXISTS (SELECT 1 FROM dbo.CompanyModules cm WHERE cm.CompanyId = c.Id AND cm.ModuleId = m.Id AND cm.Deleted = 0);

    -- 4. Role flags ---------------------------------------------------------
    -- ApplicationRole maps IsPrimaryRole / Deleted / CreatedOnUtc as non-nullable, so a NULL in any
    -- role row throws when EF reads it (login, permission checks, Roles page) - see
    -- data_fix_partner_role_nulls.sql, which fixed this for Partner only. Backfill every role.

    UPDATE dbo.AspNetRoles
    SET IsPrimaryRole = ISNULL(IsPrimaryRole, 0),
        Deleted       = ISNULL(Deleted, 0),
        CreatedOnUtc  = ISNULL(CreatedOnUtc, @now)
    WHERE IsPrimaryRole IS NULL OR Deleted IS NULL OR CreatedOnUtc IS NULL;

    -- SuperAdmin and Administrator are system roles: always full access
    UPDATE dbo.AspNetRoles SET IsPrimaryRole = 1 WHERE Name IN ('SuperAdmin', 'Administrator') AND IsPrimaryRole = 0;

    -- 5. Partner defaults: review / approve / message on WIP Review, read-only WIP Sheet Generator

    DECLARE @partnerRoleId NVARCHAR(450) = (SELECT TOP 1 Id FROM dbo.AspNetRoles WHERE Name = 'Partner');

    IF @partnerRoleId IS NOT NULL
    BEGIN
        INSERT INTO dbo.MenuPermissions (Id, MenuId, RoleId, IsView, IsManage, CreatedOnUtc, CreatedById, Deleted)
        SELECT CONVERT(NVARCHAR(36), NEWID()), mn.Id, @partnerRoleId, p.IsView, p.IsManage, @now, @by, 0
        FROM (VALUES ('M-wip-review', 1, 1), ('M-wip-sheet-generator', 1, 0)) AS p (MenuName, IsView, IsManage)
        JOIN dbo.Menus mn ON mn.MenuName = p.MenuName AND mn.Deleted = 0
        WHERE NOT EXISTS (SELECT 1 FROM dbo.MenuPermissions x WHERE x.MenuId = mn.Id AND x.RoleId = @partnerRoleId AND x.Deleted = 0);
    END

    COMMIT TRANSACTION;

    PRINT 'Role permissions seeded.';

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);

END CATCH
GO


--6

-- Clears leftover / test roles before go-live.
--
-- KEEPS (never touched):
--   SuperAdmin     - built-in super user
--   Administrator  - system role, always full access
--   Partner        - checked by name in code (login, WIP Review partner scoping)
--   SystemUser     - UsersController.CreateUser falls back to it when no role is sent
--
-- DELETES every other role that has NO users, together with the rows that point at it:
--   MenuPermissions, PermissionRecord_Role_Mapping, AspNetRoleClaims
--
-- SKIPS (and lists) any other role that still has users. AspNetUserRoles cascades on delete,
-- so deleting such a role would silently strip those users of their role. Move the users to
-- another role on the Users page first, then run this again.
--
-- HOW TO RUN
--   1. Run as is: @Apply = 0 only PREVIEWS what would be deleted / skipped. Nothing changes.
--   2. Check the preview, then set @Apply = 1 and run again to delete.
--   Take a database backup before running with @Apply = 1.
--
-- Safe to re-run. Run manually against the target database; there is no migrations tool in this project.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Apply BIT = 0;   -- 0 = preview only, 1 = delete

-- roles that must stay (compared case-insensitively by name)
DECLARE @Keep TABLE (Name NVARCHAR(256) PRIMARY KEY);
INSERT INTO @Keep (Name) VALUES ('SuperAdmin'), ('Administrator'), ('Partner'), ('SystemUser');

-- every role with what references it, and what will happen to it
DECLARE @Roles TABLE
(
    Id NVARCHAR(450) PRIMARY KEY,
    Name NVARCHAR(256),
    Users INT,
    MenuPermissions INT,
    Action NVARCHAR(40)
);

INSERT INTO @Roles (Id, Name, Users, MenuPermissions, Action)
SELECT r.Id,
       r.Name,
       (SELECT COUNT(*) FROM dbo.AspNetUserRoles ur WHERE ur.RoleId = r.Id),
       (SELECT COUNT(*) FROM dbo.MenuPermissions mp WHERE mp.RoleId = r.Id),
       CASE
           WHEN EXISTS (SELECT 1 FROM @Keep k WHERE k.Name = r.Name) THEN 'KEEP (required)'
           WHEN EXISTS (SELECT 1 FROM dbo.AspNetUserRoles ur WHERE ur.RoleId = r.Id) THEN 'SKIP (has users)'
           ELSE 'DELETE'
       END
FROM dbo.AspNetRoles r;

-- preview
SELECT Action, Name, Users, MenuPermissions
FROM @Roles
ORDER BY CASE Action WHEN 'DELETE' THEN 1 WHEN 'SKIP (has users)' THEN 2 ELSE 3 END, Name;

IF @Apply = 0
BEGIN
    PRINT 'Preview only - nothing was deleted. Set @Apply = 1 to delete the roles marked DELETE.';
    RETURN;   -- ends this batch only; the scripts below run in their own batches
END

BEGIN TRANSACTION;

BEGIN TRY

    DECLARE @ToDelete TABLE (Id NVARCHAR(450) PRIMARY KEY);
    INSERT INTO @ToDelete (Id) SELECT Id FROM @Roles WHERE Action = 'DELETE';

    -- child rows first (MenuPermissions and PermissionRecord_Role_Mapping have no cascade)
    DELETE FROM dbo.MenuPermissions WHERE RoleId IN (SELECT Id FROM @ToDelete);
    PRINT CONCAT('MenuPermissions rows deleted: ', @@ROWCOUNT);

    DELETE FROM dbo.PermissionRecord_Role_Mapping WHERE Role_Id IN (SELECT Id FROM @ToDelete);
    PRINT CONCAT('PermissionRecord_Role_Mapping rows deleted: ', @@ROWCOUNT);

    DELETE FROM dbo.AspNetRoleClaims WHERE RoleId IN (SELECT Id FROM @ToDelete);
    PRINT CONCAT('AspNetRoleClaims rows deleted: ', @@ROWCOUNT);

    -- the roles themselves (double-check: still no users, never a kept role)
    DELETE r
    FROM dbo.AspNetRoles r
    WHERE r.Id IN (SELECT Id FROM @ToDelete)
      AND NOT EXISTS (SELECT 1 FROM dbo.AspNetUserRoles ur WHERE ur.RoleId = r.Id)
      AND NOT EXISTS (SELECT 1 FROM @Keep k WHERE k.Name = r.Name);
    PRINT CONCAT('Roles deleted: ', @@ROWCOUNT);

    COMMIT TRANSACTION;

    -- what is left
    SELECT r.Name AS RemainingRole,
           (SELECT COUNT(*) FROM dbo.AspNetUserRoles ur WHERE ur.RoleId = r.Id) AS Users
    FROM dbo.AspNetRoles r
    ORDER BY r.Name;

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);

END CATCH
GO


--7

-- Gives the Administrator role access to everything.
--
-- How full access works (see Vsky.Services/Permissions/PermissionService.cs):
--   - a role with AspNetRoles.IsPrimaryRole = 1 passes every permission check (View and Manage on every page)
--   - but the sidebar only lists pages whose menu and module are Active and, for users that belong to
--     a company, whose module is switched on for that company in dbo.CompanyModules
--
-- So this script:
--   1. creates the Administrator role if it is missing
--   2. marks it as a system role (IsPrimaryRole = 1), not deleted, and fills any NULL flags
--   3. switches every active module on for every company (CompanyModules)
--   4. gives it View + Manage on every menu in dbo.MenuPermissions - not needed while IsPrimaryRole = 1,
--      but it keeps the access in place if the flag is ever cleared, and shows up in reports
--   5. lists the result
--
-- Run after create_role_permissions_tables.sql and seed_role_permissions.sql (it needs the menus).
-- Safe to re-run. Restart the API afterwards (or wait 10 minutes): permissions are cached in memory.
-- Run manually against the target database; there is no migrations tool in this project.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRANSACTION;

BEGIN TRY

    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    DECLARE @by NVARCHAR(450) = 'data_administrator_full_access';

    -- 1. Administrator role -------------------------------------------------
    -- created as a shared role (no company) when missing; an existing one keeps its company

    IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE Name = 'Administrator')
    BEGIN
        INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp, CompanyId, IsPrimaryRole, CreatedOnUtc, CreatedById, Deleted)
        VALUES (CONVERT(NVARCHAR(36), NEWID()), 'Administrator', 'ADMINISTRATOR', CONVERT(NVARCHAR(36), NEWID()), NULL, 1, @now, @by, 0);
        PRINT 'Created the Administrator role.';
    END

    DECLARE @adminRoleId NVARCHAR(450) = (SELECT TOP 1 Id FROM dbo.AspNetRoles WHERE Name = 'Administrator');

    -- 2. System role flags (NULLs crash EF when it reads the role) -----------

    UPDATE dbo.AspNetRoles
    SET IsPrimaryRole = 1,
        Deleted       = 0,
        CreatedOnUtc  = ISNULL(CreatedOnUtc, @now),
        UpdatedOnUtc  = @now,
        UpdatedById   = @by
    WHERE Id = @adminRoleId
      AND (ISNULL(IsPrimaryRole, 0) = 0 OR ISNULL(Deleted, 1) = 1 OR CreatedOnUtc IS NULL);
    PRINT CONCAT('Administrator role flags fixed: ', @@ROWCOUNT);

    -- 3. Every active module switched on for every company -------------------

    -- re-activate switches that were turned off or soft-deleted
    UPDATE cm
    SET Active = 1, Deleted = 0, UpdatedOnUtc = @now, UpdatedById = @by
    FROM dbo.CompanyModules cm
    JOIN dbo.Modules m ON m.Id = cm.ModuleId AND m.Active = 1 AND m.Deleted = 0
    WHERE (cm.Active = 0 OR cm.Deleted = 1)
      -- only one row per company + module: skip a switched-off row when an active one also exists
      AND NOT EXISTS (SELECT 1 FROM dbo.CompanyModules x
                      WHERE x.CompanyId = cm.CompanyId AND x.ModuleId = cm.ModuleId AND x.Active = 1 AND x.Deleted = 0);
    PRINT CONCAT('Company module switches turned on: ', @@ROWCOUNT);

    -- add the switches that don't exist yet
    INSERT INTO dbo.CompanyModules (Id, CompanyId, ModuleId, Active, CreatedOnUtc, CreatedById, Deleted)
    SELECT CONVERT(NVARCHAR(36), NEWID()), c.Id, m.Id, 1, @now, @by, 0
    FROM dbo.Company c
    CROSS JOIN dbo.Modules m
    WHERE m.Active = 1 AND m.Deleted = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.CompanyModules cm WHERE cm.CompanyId = c.Id AND cm.ModuleId = m.Id);
    PRINT CONCAT('Company module switches added: ', @@ROWCOUNT);

    -- 4. View + Manage on every menu -----------------------------------------

    -- upgrade the rows it already has
    UPDATE dbo.MenuPermissions
    SET IsView = 1, IsManage = 1, Deleted = 0, UpdatedOnUtc = @now, UpdatedById = @by
    WHERE RoleId = @adminRoleId
      AND MenuId IN (SELECT Id FROM dbo.Menus WHERE Deleted = 0)
      AND (IsView = 0 OR IsManage = 0 OR Deleted = 1);
    PRINT CONCAT('Administrator permissions upgraded: ', @@ROWCOUNT);

    -- add the menus it has no row for
    INSERT INTO dbo.MenuPermissions (Id, MenuId, RoleId, IsView, IsManage, CreatedOnUtc, CreatedById, Deleted)
    SELECT CONVERT(NVARCHAR(36), NEWID()), mn.Id, @adminRoleId, 1, 1, @now, @by, 0
    FROM dbo.Menus mn
    WHERE mn.Deleted = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.MenuPermissions x WHERE x.MenuId = mn.Id AND x.RoleId = @adminRoleId);
    PRINT CONCAT('Administrator permissions added: ', @@ROWCOUNT);

    COMMIT TRANSACTION;

    -- 5. Result ---------------------------------------------------------------

    SELECT r.Name AS Role, r.IsPrimaryRole AS FullAccess,
           (SELECT COUNT(*) FROM dbo.AspNetUserRoles ur WHERE ur.RoleId = r.Id) AS Users
    FROM dbo.AspNetRoles r
    WHERE r.Id = @adminRoleId;

    SELECT md.Name AS Module, mn.DisplayName AS Page, mp.IsView AS [View], mp.IsManage AS [Manage]
    FROM dbo.Menus mn
    JOIN dbo.Modules md ON md.Id = mn.ModuleId
    LEFT JOIN dbo.MenuPermissions mp ON mp.MenuId = mn.Id AND mp.RoleId = @adminRoleId AND mp.Deleted = 0
    WHERE mn.Deleted = 0
    ORDER BY md.Sortorder, mn.Sortorder;

    PRINT 'Administrator now has full access. Restart the API so the cached permissions refresh.';

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);

END CATCH
GO


--8

SET QUOTED_IDENTIFIER ON;

UPDATE dbo.MessageTemplate
SET Subject = N'Your WIP Billing login details',
    Body    = N'Dear %User.FirstName% %User.LastName%,<br><br>'
            + N'Your WIP Billing account is ready. Here are your login details:<br><br>'
            + N'<b>Website:</b> https://wipapp.moorecolson.com/auth/login<br>'
            + N'<b>Username:</b> %User.Username%<br>'
            + N'<b>Password:</b> %User.Password%<br><br>'
            + N'For your security, please change your password after you first log in.<br><br>'
            + N'Kind regards,<br>WIP Billing'
WHERE Name = N'User.WelcomeMessage';
GO


--9
-- Adds the "Partners" page to the sidebar: one top-level dbo.Menus row in the WIP Billing module,
-- placed right below WIP Review (Sortorder 3). Same row as in seed_role_permissions.sql, for
-- databases already seeded.
--
-- Administrators (system roles) see it straight away; other roles need View (and Manage for the
-- Refresh button) ticked on Roles & Permissions.
--
-- Safe to re-run: the insert is guarded, and a Partners row added earlier as a WIP Review sub-menu
-- is moved back to the top level.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRANSACTION;

BEGIN TRY

    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    DECLARE @by NVARCHAR(450) = 'data_add_partners_menu';
    DECLARE @modWip NVARCHAR(450) = 'B5C1A3E0-7D2F-4C61-9A4E-0F1D2C3B4A01';

    IF NOT EXISTS (SELECT 1 FROM dbo.Menus WHERE MenuName = 'M-partners' AND Deleted = 0)
        INSERT INTO dbo.Menus (Id, ModuleId, MenuName, DisplayName, Sortorder, ParentMenuId, Active, Link, Icon, CreatedOnUtc, CreatedById, Deleted)
        VALUES ('C6D2B4F1-8E30-4D72-AB5F-1E2D3C4B5A06', @modWip, 'M-partners', 'Partners', 3, NULL, 1,
                '/partner/wip-review/partners', 'fa-solid fa-user-tie', @now, @by, 0);

    UPDATE dbo.Menus
    SET ParentMenuId = NULL
    WHERE MenuName = 'M-partners' AND Deleted = 0 AND ParentMenuId IS NOT NULL;

    COMMIT TRANSACTION;

    SELECT m.MenuName, m.DisplayName, m.Link, m.Sortorder
    FROM dbo.Menus m
    WHERE m.MenuName = 'M-partners';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO


--10
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

    DECLARE @RoleIds TABLE (Id NVARCHAR(450) PRIMARY KEY);

    INSERT INTO @RoleIds (Id)
    SELECT Id
    FROM dbo.AspNetRoles
    WHERE UPPER(LTRIM(RTRIM(Name))) IN ('PARENT', 'PARTNER', 'STUDENT')
       OR UPPER(LTRIM(RTRIM(NormalizedName))) IN ('PARENT', 'PARTNER', 'STUDENT');

    DELETE FROM dbo.MenuPermissions               WHERE RoleId  IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.PermissionRecord_Role_Mapping WHERE Role_Id IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.AspNetRoleClaims              WHERE RoleId  IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.AspNetUserRoles               WHERE RoleId  IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.AspNetRoles                   WHERE Id      IN (SELECT Id FROM @RoleIds);

    PRINT CONCAT('Roles deleted: ', @@ROWCOUNT);

COMMIT TRANSACTION;
GO


--9
-- Adds the "Partners" page to the sidebar: one top-level dbo.Menus row in the WIP Billing module,
-- placed right below WIP Review (Sortorder 3). Same row as in seed_role_permissions.sql, for
-- databases already seeded.
--
-- Administrators (system roles) see it straight away; other roles need View (and Manage for the
-- Refresh button) ticked on Roles & Permissions.
--
-- Safe to re-run: the insert is guarded, and a Partners row added earlier as a WIP Review sub-menu
-- is moved back to the top level.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRANSACTION;

BEGIN TRY

    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    DECLARE @by NVARCHAR(450) = 'data_add_partners_menu';
    DECLARE @modWip NVARCHAR(450) = 'B5C1A3E0-7D2F-4C61-9A4E-0F1D2C3B4A01';

    IF NOT EXISTS (SELECT 1 FROM dbo.Menus WHERE MenuName = 'M-partners' AND Deleted = 0)
        INSERT INTO dbo.Menus (Id, ModuleId, MenuName, DisplayName, Sortorder, ParentMenuId, Active, Link, Icon, CreatedOnUtc, CreatedById, Deleted)
        VALUES ('C6D2B4F1-8E30-4D72-AB5F-1E2D3C4B5A06', @modWip, 'M-partners', 'Partners', 3, NULL, 1,
                '/partner/wip-review/partners', 'fa-solid fa-user-tie', @now, @by, 0);

    UPDATE dbo.Menus
    SET ParentMenuId = NULL
    WHERE MenuName = 'M-partners' AND Deleted = 0 AND ParentMenuId IS NOT NULL;

    COMMIT TRANSACTION;

    SELECT m.MenuName, m.DisplayName, m.Link, m.Sortorder
    FROM dbo.Menus m
    WHERE m.MenuName = 'M-partners';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH


--10
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

    DECLARE @RoleIds TABLE (Id NVARCHAR(450) PRIMARY KEY);

    INSERT INTO @RoleIds (Id)
    SELECT Id
    FROM dbo.AspNetRoles
    WHERE UPPER(LTRIM(RTRIM(Name))) IN ('PARENT', 'PARTNER', 'STUDENT')
       OR UPPER(LTRIM(RTRIM(NormalizedName))) IN ('PARENT', 'PARTNER', 'STUDENT');

    DELETE FROM dbo.MenuPermissions               WHERE RoleId  IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.PermissionRecord_Role_Mapping WHERE Role_Id IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.AspNetRoleClaims              WHERE RoleId  IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.AspNetUserRoles               WHERE RoleId  IN (SELECT Id FROM @RoleIds);
    DELETE FROM dbo.AspNetRoles                   WHERE Id      IN (SELECT Id FROM @RoleIds);

    PRINT CONCAT('Roles deleted: ', @@ROWCOUNT);

COMMIT TRANSACTION;

