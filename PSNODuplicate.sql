/****** Object:  StoredProcedure [dbo].[UploadAssemblyWiseBooth]    Script Date: 3/13/2023 10:32:06 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[UploadAssemblyWiseBooth]
(
	@District VARCHAR(500),
	@Assembly VARCHAR(500),
	@tbl AS dbo.UT_UploadAssemblyWiseBooth READONLY,
    @username varchar(200)='',
	@IpAddress varchar(100)=''

)
AS
BEGIN
	DECLARE @accode varchar(200) = ''
	CREATE TABLE #upBooth
	(
		id INT IDENTITY(1,1) PRIMARY KEY,
		CameraDID varchar(100),
		--ProURL varchar(100),
		--ServerName varchar(100),
		PSNo varchar(100),
		Location varchar(max),
		Operator_Name varchar(100),
		Operator_Designation varchar(100),
		Operator_Mobile_No varchar(100),
		IsOutside_booth BIT,
		IsPink_booth BIT,
		isARO BIT,
		IsAICamera BIT,
		boothid INT default(0),
		streamid INT default(0),
		operatorid INT default(0),
		ErrorMessage VARCHAR(MAX) default(''),
		Action varchar(50) default(''),
		rn INT
	)

	INSERT INTO #upBooth (CameraDID,PSNo,Location,Operator_Name,Operator_Mobile_No,Operator_Designation,
				IsOutside_booth,IsPink_booth,isARO,IsAICamera)
	SELECT CameraDID,LTRIM(RTRIM(Part_No+ '' + PSNo)),Location,Operator_Name,Operator_Mobile_No,Operator_Designation,
				IsOutside_booth,IsPink_booth,isARO,IsAICamera FROM @tbl

	SELECT @accode = accode FROM district WHERE district = @District AND acname = @Assembly

	UPDATE u
	SET streamid = s.id
	FROM #upBooth u
	INNER JOIN streamlist s ON s.deviceid = u.CameraDID

	--INSERT INTO streamlist (deviceid,streamname,prourl,servername,schoolid,status,lastseen,IsAICamera,AddedBy,AddedFrom)
	--SELECT CameraDID,CameraDID,ProURL,ServerName,'9999','STOPPED','1970-01-01 00:00:00.000',IsAICamera,@username,'EXCEL'
	--FROM #upBooth WHERE streamid = 0 AND CameraDID <> '' AND ProURL <> '' AND ServerName <> ''

	UPDATE u
	SET streamid = s.id
	FROM #upBooth u
	INNER JOIN streamlist s ON s.deviceid = u.CameraDID AND u.streamid = 0

	UPDATE u
	SET ErrorMessage = 'CameraDID does not exists.'
	FROM #upBooth u
	WHERE u.streamid = 0
	-------------------Add By Rahul-----------------------------
	--	 DECLARE @count int
 --        SET @count =(SELECT COUNT(b1.id) FROM (SELECT b1.id,COUNT(id) OVER (PARTITION BY streamid) as cnt 
	--		FROM #upBooth b1) b1 WHERE cnt > 1)
	--		IF (@count <=0)        
	--		BEGIN   
	--			SET @count = 0      
	--		END
	--		ELSE
	--		BEGIN
	--			SET @count=@count-1
	--		END
	
	--UPDATE u SET ErrorMessage = 'This CameraDID is duplicate in Excel'
	--FROM #upBooth u where id IN 
	--(SELECT Top(@count) b1.id FROM (SELECT b1.id,COUNT(id) OVER (PARTITION BY streamid) as cnt 	FROM #upBooth b1
 --    ) b1 WHERE cnt > 1 order by id desc) and u.streamid !=0 
	-- -----------------End-----------------------------

	UPDATE u
	SET ErrorMessage = 'This CameraDID is already assigned to District = ' + b.district + ' | Assembly = ' + b.acname + ' | PSNO = ' + b.PSNum + '.'
	FROM #upBooth u
	INNER JOIN booth b on b.streamid = u.streamid
	WHERE u.streamid != 0 AND (b.PSNum != u.PSNo OR b.location != u.Location OR b.district != @District OR b.acname != @Assembly)  
	AND ISNULL(isdelete,0) = 0
	

	UPDATE u
	SET operatorid = o.id
	FROM #upBooth u
	INNER JOIN operator_info o ON o.operatorName = u.Operator_Name AND o.operatorNumber = u.Operator_Mobile_No

	DECLARE @dummyOpID INT = 0
	SELECT @dummyOpID = id FROM operator_info WHERE operatorName = 'NA' AND operatorNumber='9876543210'

	IF (@dummyOpID = 0)
	BEGIN
		INSERT INTO operator_info(operatorName,operatorNumber,Designation)
		VALUES('NA','9876543210','NA')
		SET @dummyOpID = @@IDENTITY
	END

	UPDATE u
	SET operatorid = @dummyOpID
	FROM #upBooth u
	WHERE ISNULL(Operator_Name,'') = '' AND ISNULL(Operator_Mobile_No,'') = ''
		AND ISNULL(Operator_Designation,'') = ''

	INSERT INTO operator_info(operatorName,operatorNumber,Designation)
	SELECT Operator_Name,Operator_Mobile_No,Operator_Designation FROM #upBooth WHERE operatorid = 0
	AND ISNULL(Operator_Name,'') <> '' AND ISNULL(Operator_Mobile_No,'') <> '' AND ISNULL(Operator_Designation,'') <> ''

	UPDATE u
	SET operatorid = o.id
	FROM #upBooth u
	INNER JOIN operator_info o ON o.operatorName = u.Operator_Name AND o.operatorNumber = u.Operator_Mobile_No

	UPDATE u
	SET boothid = b.id,Action='UPDATE'
	FROM #upBooth u
	INNER JOIN booth b ON b.PSNum = u.PSNo and b.location = u.Location AND b.district = @District AND b.acname = @Assembly AND ISNULL(isdelete,0) = 0

	UPDATE b
	SET isdelete = 1,updatedBy = @username,updatedDate = [dbo].[GETIST](),
		updatedFrom = 'EXCEL',UpdatedFromPage='BoothMaster.aspx'
	FROM boothhistory b
	INNER JOIN #upBooth u ON u.boothid = b.boothid AND ISNULL(b.isdelete,0) = 0 and u.Action='UPDATE'

	UPDATE #upBooth
	SET rn = b.rn2
	FROM #upBooth u
	inner join (
		SELECT *
		,ROW_NUMBER() OVER(PARTITION BY CameraDID,@District,@accode,@Assembly,PSNo,location ORDER BY @District,@accode,@Assembly,PSNo,location) rn2
		FROM #upBooth u
		WHERE /*boothid = 0 AND*/ streamid != 0 AND ISNULL(ErrorMessage,'') = ''
	) b on u.id=b.id

	UPDATE u
	SET ErrorMessage = 'This record is duplicate in Excel.'
	FROM #upBooth u
	WHERE u.rn > 1

	UPDATE #upBooth
	SET rn = b.rn2
	FROM #upBooth u
	inner join (
		SELECT *
		,ROW_NUMBER() OVER(PARTITION BY CameraDID ORDER BY @District,@accode,@Assembly,PSNo,location) rn2
		FROM #upBooth u
		WHERE boothid = 0 AND streamid != 0 AND ISNULL(ErrorMessage,'') = '' and rn<=1
	) b on u.id=b.id

	UPDATE u
	SET ErrorMessage = 'This CameraDID is duplicate in Excel.'
	FROM #upBooth u
	WHERE u.rn > 1

	UPDATE #upBooth
	SET rn = b.rn2
	FROM #upBooth u
	inner join (
		SELECT *
		,ROW_NUMBER() OVER(PARTITION BY @District,@accode,@Assembly,PSNo,location ORDER BY @District,@accode,@Assembly,PSNo,location) rn2
		FROM #upBooth u
		WHERE boothid = 0 AND streamid != 0 AND ISNULL(ErrorMessage,'') = '' and rn<=1
	) b on u.id=b.id

	UPDATE u
	SET ErrorMessage = 'This record is duplicate in Excel.'
	FROM #upBooth u
	WHERE u.rn > 1
	--Added by astha--
			UPDATE #upBooth
	SET rn = b.rn2
	FROM #upBooth u
	inner join (
		SELECT *
		,ROW_NUMBER() OVER(PARTITION BY PSNo ORDER BY @District,@accode,@Assembly,PSNo,location) rn2
		FROM #upBooth u
		WHERE boothid = 0 AND streamid != 0 AND ISNULL(ErrorMessage,'') = '' and rn<=1
	) b on u.id=b.id

	UPDATE u
	SET ErrorMessage = 'This PSNo is Duplicate'
	FROM #upBooth u
	WHERE u.rn > 1
	--end by astha
	INSERT INTO booth(streamid,operatorid,district,accode,acname,PSNum,location,boothstateid,isdisplay,
	updatedBy,updatedDate,updatedFrom,longitude,latitude,bkpstreamid,cameralocationtype,
	IsPink,IsOutsideBooth,AddDatetime,addedBy,IsAro,Trial1,Trial2,isdelete,AddedFromPage,AddedFrom,isupdated)  --Add column isupdate by Rahul 
	SELECT streamid,operatorid,district,accode,acname,PSNo,location,boothstateid,isdisplay,
	updatedBy,updatedDate,updatedFrom,longitude,latitude,CameraDID,cameralocationtype,
	IsPink_booth,IsOutside_booth,AddDatetime,addedBy,IsAro,Trial1,Trial2,isdelete,AddedFromPage,AddedFrom,isupdated FROM (
		SELECT streamid,operatorid,@District AS district,@accode AS accode,@Assembly AS acname,PSNo,location,1 as boothstateid,1 as isdisplay,
		@username as updatedBy,[dbo].[GETIST]() as updatedDate,'EXCEL' AS updatedFrom,0 AS longitude,0 AS latitude,CameraDID,CASE WHEN IsOutside_booth = 1 THEN 'Outside' ELSE 'Inside' END AS cameralocationtype,
		IsPink_booth,IsOutside_booth,[dbo].[GETIST]() AS AddDatetime,@username AS addedBy,IsAro,0 AS Trial1,0 AS Trial2,0 AS isdelete,'BoothMaster.aspx' AS AddedFromPage,'EXCEL' AS AddedFrom,0 AS isupdated
		,ROW_NUMBER() OVER(PARTITION BY @District,@accode,@Assembly,PSNo,location ORDER BY @District,@accode,@Assembly,PSNo,location) rn
		FROM #upBooth
		WHERE boothid = 0 AND streamid != 0 AND ISNULL(ErrorMessage,'') = ''
	) tbl WHERE rn = 1

	UPDATE u
	SET boothid = b.id,Action='INSERT'
	FROM #upBooth u
	INNER JOIN booth b ON b.PSNum = u.PSNo and b.location = u.Location AND b.district = @District AND b.acname = @Assembly
		and u.boothid = 0 and ISNULL(b.isdelete,0)=0

	INSERT INTO boothhistory(streamid,operatorid,district,accode,acname,PSNum,location,boothstateid,isdisplay,
	updatedBy,updatedDate,updatedFrom,longitude,latitude,bkpstreamid,cameralocationtype,
	IsPink,IsOutsideBooth,AddDatetime,addedBy,IsAro,Trial1,Trial2,isdelete,AddedFromPage,AddedFrom,Action,boothid,IPAddress)
	SELECT streamid,operatorid,@District,@accode,@Assembly,PSNo,location,1,1,
	@username,[dbo].[GETIST](),'EXCEL',0,0,CameraDID,CASE WHEN IsOutside_booth = 1 THEN 'Outside' ELSE 'Inside' END,
	IsPink_booth,IsOutside_booth,[dbo].[GETIST](),@username,IsAro,0,0,0,'BoothMaster.aspx','EXCEL','INSERT',boothid,@IpAddress  FROM #upBooth
	WHERE boothid != 0 AND streamid != 0 AND ISNULL(ErrorMessage,'') = '' AND Action = 'INSERT'

	UPDATE b
	SET
		location = u.Location,streamid = u.streamid, operatorid = u.operatorid,
		cameralocationtype = CASE WHEN IsOutside_booth = 1 THEN 'Outside' ELSE 'Inside' END,
		IsOutsideBooth = IsOutside_booth, IsPink = IsPink,IsAro = u.isARO,
		updatedBy = @username,updatedDate = [dbo].[GETIST](),updatedFrom = 'EXCEL'
		,isupdated = 1,UpdatedFromPage='BoothMaster.aspx'
	FROM booth b
	INNER JOIN #upBooth u ON b.PSNum = u.PSNo AND b.location = u.Location AND b.district = @District AND b.acname = @Assembly
		AND u.boothid = b.id AND Action = 'UPDATE' and ISNULL(b.isdelete,0)=0

	--UPDATE b
	--SET
	--	isdelete = 1,updatedBy = @username,updatedDate = [dbo].[GETIST](),
	--	updatedFrom = 'EXCEL',UpdatedFromPage='BoothMaster.aspx'
	--FROM boothhistory b
	--INNER JOIN #upBooth u ON u.boothid = b.id AND b.isdelete = 0
	--	AND ISNULL(u.ErrorMessage,'') = '' AND u.Action = 'UPDATE'

	INSERT INTO boothhistory(streamid,operatorid,district,accode,acname,PSNum,location,boothstateid,isdisplay,
	updatedBy,updatedDate,updatedFrom,longitude,latitude,bkpstreamid,cameralocationtype,
	IsPink,IsOutsideBooth,AddDatetime,addedBy,IsAro,Trial1,Trial2,isdelete,AddedFromPage,AddedFrom,Action,boothid,IPAddress)
	SELECT DISTINCT streamid,operatorid,@District,@accode,@Assembly,PSNo,location,1,1,
	@username,[dbo].[GETIST](),'EXCEL',0,0,CameraDID,CASE WHEN IsOutside_booth = 1 THEN 'Outside' ELSE 'Inside' END,
	IsPink_booth,IsOutside_booth,[dbo].[GETIST](),@username,IsAro,0,0,0,'BoothMaster.aspx','EXCEL','UPDATE',boothid,@IpAddress
	FROM #upBooth
	WHERE boothid != 0 AND streamid != 0 AND ISNULL(ErrorMessage,'') = '' AND Action = 'UPDATE'

	SELECT CameraDID, PSNo, Location, Operator_Name, Operator_Mobile_No, Operator_Designation, 
		IsOutside_booth,IsPink_booth,isARO,IsAICamera,ErrorMessage
	FROM #upBooth WHERE ISNULL(ErrorMessage,'') != ''
END

