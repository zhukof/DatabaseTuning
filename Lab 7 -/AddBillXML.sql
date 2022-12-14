USE [EducationDatabase]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[AddBillXML]
	@employeeID INT,
	@buyerID INT,
	@doc XML
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ COMMITTED
    BEGIN TRANSACTION

	-- Добавляем временную таблицу
	CREATE TABLE #BillItemXML
	(BillId INT, ProductId INT, Quantity INT)

	-- Парсим XML и добавляем во временную таблицу
	DECLARE @idoc int

	EXEC sp_xml_preparedocument @idoc OUTPUT, @doc

	INSERT INTO #BillItemXML
	SELECT BillId, ProductId, SUM(Quantity)
	FROM OPENXML (@idoc, '/root/bill/product', 2)
		 WITH (BillId int '../@billId',
			 ProductId int '@productId',
			 Quantity int '@quantity')
	GROUP BY ProductId, BillId
	
	EXEC sp_xml_removedocument @idoc;

	-- Удаляем из временной таблицы продукты, которые не удовлетворяют нужному количеству
	DELETE biXML
	FROM #BillItemXML AS biXML
	INNER JOIN Product product ON biXML.ProductID = Product.ProductID
	WHERE biXML.Quantity > product.Quantity

	-- Обновляем таблицу Product в самом начале, что бы условно зарезервировать продукты
	UPDATE product
	SET Quantity = product.Quantity - biXML.Quantity
	FROM Product product
	INNER JOIN #BillItemXML biXML ON product.ProductID = biXML.ProductID

	-- Если чек не найден, проставляем во временной таблице BillID нового чека
	IF NOT EXISTS(SELECT 1 FROM Bill WHERE BillID IN (SELECT DISTINCT BillID FROM #BillItemXML))
		BEGIN
			DECLARE @BillId int
			EXEC	[dbo].[AddBill]
					@BuyerID = @buyerID,
					@EmployeeID = @employeeID,
					@BillId = @BillId OUTPUT
			
			UPDATE #BillItemXML
			SET BillId = @BillId
		END
	
	-- Добавляем элементы чека
	INSERT INTO BillItem(BillID, ProductID, Number, Cost, Date)
	SELECT	biXML.BillID,
			biXML.ProductId,
			biXML.Quantity,
			product.Price * biXML.Quantity,
			GETDATE() AS Date
	FROM #BillItemXML AS biXML
	INNER JOIN Product product ON product.ProductID = biXML.ProductID

	COMMIT TRANSACTION 
END
