package tool.lt;

class TileTool extends tool.LayerTool<data.LedTypes.TilesetSelection> {
	public var curTilesetDef(get,never) : Null<data.def.TilesetDef>;
	inline function get_curTilesetDef() return editor.project.defs.getTilesetDef( editor.curLayerInstance.def.tilesetDefUid );

	public var flipX = false;
	public var flipY = false;

	public function new() {
		super();
		selectValue( getSelectedValue() );
	}

	override function getSelectionMemoryKey():Null<String> {
		return curTilesetDef==null ? super.getSelectionMemoryKey() : curTilesetDef.relPath;
	}

	override function getDefaultValue():data.LedTypes.TilesetSelection {
		return { mode:Stamp, ids:[0] };
	}

	override function canEdit():Bool {
		return super.canEdit() && curTilesetDef!=null;
	}


	public function getMode() return getSelectedValue().mode;

	public function setMode(m:data.LedTypes.TileEditMode) {
		getSelectedValue().mode = m;
	}

	public function isRandomMode() return getSelectedValue().mode==Random;

	override function useAtInterpolatedGrid(cx:Int, cy:Int):Bool {
		super.useAtInterpolatedGrid(cx, cy);

		switch curMode {
			case null, PanView:

			case Add:
				if( drawSelectionAt(cx, cy) )
					return true;

			case Remove:
				if( removeSelectedTileAt(cx, cy) )
					return true;
		}

		return false;
	}

	override function useFloodfillAt(m:MouseCoords):Bool {
		var initial : Null<Int> = curLayerInstance.getGridTileId(m.cx,m.cy);

		if( initial==getSelectedValue().ids[0] )
			return false;

		return _floodFillImpl(
			m,
			function(cx,cy) return curLayerInstance.getGridTileId(cx,cy) != initial,
			function(cx,cy,v) curLayerInstance.setGridTile(cx,cy, v.ids[0])
		);
	}

	override function useOnRectangle(m:MouseCoords, left:Int, right:Int, top:Int, bottom:Int) {
		super.useOnRectangle(m, left, right, top, bottom);

		if( curMode==Add && !isRandomMode() )
			return drawSelectionInRectangle(left,top, right-left+1, bottom-top+1);

		var anyChange = false;
		for(cx in left...right+1)
		for(cy in top...bottom+1) {
			switch curMode {
				case null, PanView:
				case Add:
					if( drawSelectionAt(cx,cy) ) // random mode only
						anyChange = true;

				case Remove:
					if( editor.curLayerInstance.hasGridTile(cx,cy) ) {
						editor.curLevelHistory.markChange(cx,cy);
						editor.curLayerInstance.removeGridTile(cx,cy);
						anyChange = true;
					}
			}
		}

		return anyChange;
	}


	function drawSelectionInRectangle(cx:Int, cy:Int, wid:Int, hei:Int) {
		var anyChange = false;
		var sel = getSelectedValue();
		var selMap = new Map();

		var selLeft = Const.INFINITE;
		var selTop = Const.INFINITE;
		var selRight = -Const.INFINITE;
		var selBottom = -Const.INFINITE;

		for(tid in sel.ids) {
			selMap.set(tid,true);
			selLeft = M.imin(selLeft, curTilesetDef.getTileCx(tid));
			selRight = M.imax(selRight, curTilesetDef.getTileCx(tid));
			selTop = M.imin(selTop, curTilesetDef.getTileCy(tid));
			selBottom = M.imax(selBottom, curTilesetDef.getTileCy(tid));
		}

		var selWid = selRight-selLeft+1;
		var selHei = selBottom-selTop+1;
		var curX = cx;
		var curY = cy;
		var gridDiffScale = M.imax(1, M.round( curTilesetDef.tileGridSize / curLayerInstance.def.gridSize ) );
		for( dx in 0...wid )
		for( dy in 0...hei ) {
			if( dx%gridDiffScale!=0 || dy%gridDiffScale!=0 )
				continue;

			var x = cx+dx;
			var y = cy+dy;

			var tid = curTilesetDef.getTileId(
				selLeft + Std.int(dx/gridDiffScale)%selWid,
				selTop + Std.int(dy/gridDiffScale)%selHei
			);

			if( curLayerInstance.isValid(x,y) && curLayerInstance.getGridTileId(x,y)!=tid && selMap.exists(tid) ) {
				curLayerInstance.setGridTile(x,y, tid);
				editor.curLevelHistory.markChange(x,y);
				anyChange = true;
			}
		}

		return anyChange;
	}

	function drawSelectionAt(cx:Int, cy:Int) {
		var anyChange = false;
		var sel = getSelectedValue();
		var flips = M.makeBitsFromBools(flipX, flipY);
		var li = curLayerInstance;

		if( isRandomMode() ) {
			// Single random tile
			var tid = sel.ids[Std.random(sel.ids.length)];
			if( li.isValid(cx,cy) && ( li.getGridTileId(cx,cy)!=tid || li.getGridTileFlips(cx,cy)!=flips ) ) {
				li.setGridTile(cx,cy, tid, flips);
				anyChange = true;
			}
		}
		else {
			// Stamp
			var left = Const.INFINITE;
			var right = 0;
			var top = Const.INFINITE;
			var bottom = 0;

			for(tid in sel.ids) {
				left = M.imin(left, curTilesetDef.getTileCx(tid));
				right = M.imax(right, curTilesetDef.getTileCx(tid));
				top = M.imin(top, curTilesetDef.getTileCy(tid));
				bottom = M.imax(bottom, curTilesetDef.getTileCy(tid));
			}

			var gridDiffScale = M.imax(1, M.round( curTilesetDef.tileGridSize / li.def.gridSize ) );
			for(tid in sel.ids) {
				var tdCx = curTilesetDef.getTileCx(tid);
				var tdCy = curTilesetDef.getTileCy(tid);
				var tcx = cx + ( flipX ? right-tdCx : tdCx-left ) * gridDiffScale;
				var tcy = cy + ( flipY ? bottom-tdCy : tdCy-top ) * gridDiffScale;
				if( li.isValid(tcx,tcy) && ( li.getGridTileId(tcx,tcy)!=tid || li.getGridTileFlips(tcx,tcy)!=flips ) ) {
					li.setGridTile(tcx,tcy,tid, flips);
					editor.curLevelHistory.markChange(tcx,tcy);
					anyChange = true;
				}
			}
		}
		return anyChange;
	}


	function removeSelectedTileAt(cx:Int, cy:Int) {
		var sel = getSelectedValue();

		var anyChange = false;
		if( isRandomMode() ) {
			if( editor.curLayerInstance.hasGridTile(cx,cy) ) {
				editor.curLayerInstance.removeGridTile(cx,cy);
				anyChange = true;
			}
		}
		else {
			var left = Const.INFINITE;
			var top = Const.INFINITE;

			for(tid in sel.ids) {
				left = M.imin(left, curTilesetDef.getTileCx(tid));
				top = M.imin(top, curTilesetDef.getTileCy(tid));
			}

			var gridDiffScale = M.imax(1, M.round( curTilesetDef.tileGridSize / curLayerInstance.def.gridSize ) );
			for(tid in sel.ids) {
				var tcx = cx + ( curTilesetDef.getTileCx(tid) - left ) * gridDiffScale;
				var tcy = cy + ( curTilesetDef.getTileCy(tid) - top ) * gridDiffScale;
				if( editor.curLayerInstance.hasGridTile(tcx,tcy) ) {
					editor.curLayerInstance.removeGridTile(tcx,tcy);
					editor.curLevelHistory.markChange(tcx,tcy);
					anyChange = true;
				}
			}
		}

		return anyChange;
	}

	override function updateCursor(m:MouseCoords) {
		super.updateCursor(m);

		if( curTilesetDef==null || !curTilesetDef.isAtlasLoaded() ) {
			editor.cursor.set(None);
			return;
		}

		if( isRunning() && rectangle ) {
			var r = Rect.fromMouseCoords(origin, m);
			editor.cursor.set( GridRect(curLayerInstance, r.left, r.top, r.wid, r.hei) );
		}
		else if( curLayerInstance.isValid(m.cx,m.cy) ) {
			var sel = getSelectedValue();
			var flips = M.makeBitsFromBools(flipX, flipY);
			if( isRandomMode() )
				editor.cursor.set( Tiles(curLayerInstance, [ sel.ids[Std.random(sel.ids.length)] ], m.cx, m.cy, flips) );
			else
				editor.cursor.set( Tiles(curLayerInstance, sel.ids, m.cx, m.cy, flips) );
		}
		else
			editor.cursor.set(None);
	}

	override function createToolPalette():ui.ToolPalette {
		return new ui.palette.TilePalette(this);
	}

	public function saveSelection() {
		curTilesetDef.saveSelection( getSelectedValue() );
		editor.ge.emit( TilesetSelectionSaved(curTilesetDef) );
		N.msg("Saved selection");
	}

	override function onKeyPress(keyId:Int) {
		super.onKeyPress(keyId);

		if( !App.ME.hasAnyToggleKeyDown() && !Editor.ME.hasInputFocus() )
			switch keyId {
				case K.R :
					setMode( isRandomMode() ? Stamp : Random );
					editor.ge.emit(ToolOptionChanged);
					palette.render();

				case K.S:
					saveSelection();

				case K.X:
					flipX = !flipX;
					N.quick("X-flip: "+L.onOff(flipX));
					updateCursor(lastMouse);

				case K.Y, K.Z:
					flipY = !flipY;
					N.quick("Y-flip: "+L.onOff(flipY));
					updateCursor(lastMouse);
			}
	}
}
