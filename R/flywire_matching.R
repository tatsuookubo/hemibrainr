# FlyWire neuron matching

#' @rdname hemibrain_add_made_matches
#' @export
flywire_matching_rewrite <- function(flywire.ids = names(flywire_neurons()),
                                     meta = flywire_neurons()[,],
                                     catmaid.update = TRUE,
                                     selected_file  = options()$hemibrainr_matching_gsheet, # 1_RXfVRw2nVjzk6yXOKiOr_JKwqk2dGSVG_Xe7_v8roU
                                     reorder = FALSE,
                                     top.nblast = FALSE,
                                     nblast = NULL,
                                     ...){
  # Get the FAFB matching Google sheet
  gs = hemibrain_match_sheet(sheet = "FAFB", selected_file = selected_file)
  skids = as.character(unique(gs$skid))

  # Get FAFBv14 coordinates
  if(length(skids) & catmaid.update){
    cats = nat::neuronlist()
    batches = split(1:length(skids), round(seq(from = 1, to = 100, length.out = length(skids))))
    all.ids = c()
    for(i in 1:length(batches)){
      # Read CATMAID neurons
      message("Batch:", i, "/10")
      search = skids[batches[[i]]]
      cat = tryCatch(catmaid::read.neurons.catmaid(search, OmitFailures = TRUE), error = function(e) NULL)
      if(!length(cat)){
        next
      }
      cats = nat::union(cats,cat)

      # Get xyz for primary branch points
      simp = nat::nlapply(cat,nat::simplify_neuron,n=1, .parallel = TRUE, OmitFailures = TRUE)
      branchpoints = sapply(simp, function(y) nat::xyzmatrix(y)[ifelse(length(nat::branchpoints(y)),nat::branchpoints(y),max(nat::endpoints(y))),])
      branchpoints = t(branchpoints)
      FAFB.xyz = apply(branchpoints, 1, paste_coords)

      # Get FlyWire voxel coordinates
      branchpoints.flywire = nat.templatebrains::xform_brain(branchpoints, reference = "FlyWire", sample = "FAFB14", .parallel = TRUE, verbose = TRUE)
      rownames(branchpoints.flywire) = rownames(branchpoints)
      branchpoints.flywire.raw = scale(branchpoints.flywire, scale = c(4, 4, 40), center = FALSE)
      fw.ids = fafbseg::flywire_xyz2id(branchpoints.flywire.raw, rawcoords = TRUE)
      flywire.xyz = apply(branchpoints.flywire.raw, 1, paste_coords)

      # Add
      indices = match(names(FAFB.xyz),gs$skid)
      if(length(indices)){
        gs[indices,]$FAFB.xyz = FAFB.xyz
        gs[indices,]$flywire.xyz = flywire.xyz
        gs[indices,]$flywire.id = fw.ids
      }
    }
  }

  # Top NBLAST
  if(top.nblast){
    if(is.null(nblast)){
      nblast = tryCatch(hemibrain_nblast('hemibrain-flywire'), error = function(e) NULL)
    }
    if(!is.null(nblast)){
      nblast.top = nblast[match(gs$flywire.id,rownames(nblast)),]
      tops = apply(nblast.top,1,function(r) which.max(r))
      top = colnames(nblast)[unlist(tops)]
      top[!gs$flywire.id%in%rownames(nblast)] = NA
      gs$hemibrain.nblast.top = top
    }
  }

  # flywire svids
  svids = fafbseg::flywire_xyz2id(nat::xyzmatrix(gs$flywire.xyz), root=FALSE, rawcoords = TRUE)
  gs[,]$flywire.svid = svids

  # Update FAFB.xyz column
  empty = is.na(gs$FAFB.xyz) & ! is.na(gs$flywire.xyz)
  if(sum(empty)){
    FAFB.xyz = meta[gs[empty,"flywire.id"],"FAFB.xyz"]
    gs[empty,"FAFB.xyz"] = FAFB.xyz
  }
  empty = is.na(gs$FAFB.xyz) & ! is.na(gs$flywire.xyz)
  if(sum(empty)){
    points.raw = nat::xyzmatrix(gs[empty,"flywire.xyz"])
    points.nm = scale(points.raw, scale = c(4, 4, 40), center = FALSE)
    points.fafb = nat.templatebrains::xform_brain(points.nm, sample = "FlyWire", reference = "FAFB14", .parallel = TRUE, verbose = TRUE)
    FAFB.xyz = apply(points.fafb, 1, paste_coords)
    gs[empty,"FAFB.xyz"] = FAFB.xyz
  }

  # Update side information
  if(!is.null(meta$side)){
    # Update side
    sides = meta[match(gs$flywire.id,meta$flywire.id),"side"]
    sides[is.na(sides)] = gs$side[is.na(sides)]
    gs$side = sides
  }

  # Update
  write.cols = intersect(c("FAFB.xyz", "flywire.xyz", "flywire.id", "flywire.svid", "side", "nblast.top"),colnames(gs))
  gsheet_update_cols(
      write.cols = write.cols,
      gs=gs,
      selected_sheet = selected_file,
      sheet = "FAFB")

  # Figure out duplicate entries
  fg = hemibrain_match_sheet(sheet = "FAFB", selected_file = selected_file)
  fg$index = 1:nrow(fg)+1
  removals = data.frame()
  for(set in c('skid',"flywire.xyz","flywire.svid")){
    dupes = unique(fg[[set]][duplicated(fg[[set]])])
    dupes = id_okay(dupes)
    for(dupe in dupes){
      many = fg[[set]] == dupe
      many[is.na(many)] = FALSE
      sub = fg[many,]
      skd = unique(sub$skid)
      skd = id_okay(skd)
      if(length(skd)>1){
        next
      }
      best = which.max(apply(sub, 1, function(r) sum(!is.na(r[c("hemibrain.match", "hemibrain.match.quality",
                                                                "LM.match", "LM.match.quality",
                                                                "FAFB.hemisphere.match", "FAFB.hemisphere.match.quality")]))))
      remove = sub[-best,]
      removals = rbind(removals, remove)
    }
  }
  if(reorder & nrow(removals)){
    n = fg[!fg$index%in%removals$index,]
    n = n[order(n$User),]
    n = n[order(n$cell_body_fiber),]
    n = n[order(n$ItoLee_Hemilineage),]
    n = n[!is.na(n$flywire.xyz)|!is.na(n$skid),]
    n$index = NULL
    gsheet_manipulation(FUN = googlesheets4::write_sheet,
                        data = n[0,],
                        ss = selected_file,
                        sheet = "FAFB")
    batches = split(1:nrow(n), ceiling(seq_along(1:nrow(n))/500))
    for(i in batches){
      gsheet_manipulation(FUN = googlesheets4::sheet_append,
                          data = n[min(i):max(i),],
                          ss = selected_file,
                          sheet = "FAFB")
    }
  }else if (nrow(removals)){
    for(r in sort(removals$index,decreasing = TRUE)){
      range.del = googlesheets4::cell_rows(r)
      message("Removing a row for: ", dupe)
      gsheet_manipulation(FUN = googlesheets4::range_delete,
                          ss = selected_file,
                          range = range.del,
                          sheet = "FAFB")
    }
  }

  # Add missing flywire information
  all.ids = correct_id(unique(fg$flywire.id))
  missing = setdiff(flywire.ids, all.ids)
  if(length(missing)){
    hemibrain_matching_add(ids = missing, meta = meta, dataset="flywire", selected_file = selected_file, ...)
  }

  ## Read the LM Google Sheet
  lmg = hemibrain_match_sheet(sheet = "lm", selected_file = selected_file)
  if(nrow(lmg)){
    lmg$flywire.xyz = fg$flywire.xyz[match(lmg$id,fg$LM.match)]
    gsheet_update_cols(
      write.cols = "flywire.xyz",
      gs=lmg,
      selected_sheet = selected_file,
      sheet = "lm")
  }

  ## Read the hemibrain Google Sheet
  hg = hemibrain_match_sheet(sheet = "hemibrain", selected_file = selected_file)
  if(nrow(hg)){
    hg$flywire.xyz = fg$flywire.xyz[match(hg$bodyid,fg$hemibrain.match)]
    gsheet_update_cols(
      write.cols = "flywire.xyz",
      gs=hg,
      selected_sheet = selected_file,
      sheet = "hemibrain")
  }

}

#' @rdname hemibrain_matching
#' @export
LR_matching <- function(ids = NULL,
                        threshold = 0,
                        mirror.nblast = NULL,
                        selected_file = options()$hemibrainr_matching_gsheet,
                        batch_size = 50,
                        db = flywire_neurons(),
                        query = flywire_neurons(mirror=TRUE),
                        overwrite = c("FALSE","mine","mine_empty","TRUE"),
                        column = NULL,
                        entry = NULL){
  message("Matching mirrored flywire neurons (blue) to non-mirrored flywire neurons (red)")
  # Packages
  if(!requireNamespace("elmr", quietly = TRUE)) {
    stop("Please install elmr using:\n", call. = FALSE,
         "remotes::install_github('natverse/elmr')")
  }
  if(!requireNamespace("fafbseg", quietly = TRUE)) {
    stop("Please install fafbseg using:\n", call. = FALSE,
         "remotes::install_github('natverse/fafbseg')")
  }
  # Motivate!
  nat::nopen3d()
  plot_inspirobot()
  unsaved = saved = c()
  message("
          #######################Colours##########################
          black = FAFB CATMAID neuron,
          dark grey = flywire neuron,
          blue = mirrrored flywire neuron you are trying to match,
          red = potential hemibrain matches based on NBLAST score,
          green = a chosen hemibrain neuron during scanning,
          dark blue = your selected hemibrain match.
          #######################Colours##########################
          ")
  ## Get NBLAST
  if(is.null(mirror.nblast)){
    message("Loading flywire NBLAST from flyconnectome Google Team Drive using Google Filestream: ")
    message(file.path(options()$Gdrive_hemibrain_data,"hemibrain_nblast/flywire.mirror.mean.rda"))
    mirror.nblast = hemibrain_nblast("flywire-mirror")
  }
  # Read the Google Sheet
  gs = hemibrain_match_sheet(selected_file = selected_file, sheet = "flywire")
  id = "flywire.id"
  # Get neuron data repo
  if(missing(db)) {
    db=tryCatch(force(db), error=function(e) {
      stop("Unable to use `flywire_neurons()`. ",
           "You must load the hemibrain Google Team Drive")
    })
  }
  if(missing(query)) {
    query=tryCatch(force(query), error=function(e) {
      stop("Unable to use `flywire_neurons(mirror=TRUE)`. ",
           "You must load the hemibrain Google Team Drive")
    })
  }
  # How much is done?
  match.field = paste0("FAFB.hemisphere",".match")
  quality.field = paste0("FAFB.hemisphere",".match.quality")
  done = subset(gs, !is.na(gs[[match.field]]))
  message("Neuron matches: ", nrow(done), "/", nrow(gs))
  print(table(gs[[quality.field]]))
  # choose user
  message("Users: ", paste(sort(unique(gs$User)),collapse = " "))
  initials = must_be("Choose a user : ", answers = unique(gs$User))
  say_hello(initials)
  # choose ids
  selected = id_selector(gs=gs, ids=ids, id=id, overwrite = overwrite,
                         quality.field = quality.field, match.field = match.field,
                         initials = initials, column = column, entry = entry)
  # choose brain
  brain = elmr::FAFB.surf
  # Make matches!
  match.more = TRUE
  while(match.more){
    match_cycle = neuron_match_scanner(brain = brain,
                                       selected = selected,
                                       id = id,
                                       unsaved = unsaved,
                                       saved = saved,
                                       chosen.field = "flywire.xyz",
                                       nblast = mirror.nblast,
                                       threshold = threshold,
                                       batch_size = batch_size,
                                       targets = db,
                                       targets.repository = "flywire",
                                       query = query,
                                       extra.neurons = db,
                                       query.repository = "flywire",
                                       extra.repository = "CATMAID",
                                       match.field = match.field,
                                       quality.field = quality.field,
                                       soma.size = 400,
                                       show.columns = c("cell.type","ItoLee_Hemilineage","note"))
    selected = match_cycle[["selected"]]
    unsaved = match_cycle[["unsaved"]]
    if(length(unsaved)){
      plot_inspirobot()
      say_encouragement(initials)
      # Read!
      gs2 = hemibrain_match_sheet(selected_file = selected_file, sheet = "flywire")
      gs2[match(gs[[id]],gs2[[id]]),match.field]= selected[[match.field]][match(gs2[[id]],selected[[id]])]
      gs2[match(gs[[id]],gs2[[id]]),quality.field]=selected[[quality.field]][match(gs2[[id]],selected[[id]])]
      gs2[match(gs[[id]],gs2[[id]]),"note"]=selected[["note"]][match(gs2[[id]],selected[[id]])]
      gs2[match(gs[[id]],gs2[[id]]),"User"]= initials
      # Write!
      write_matches(gs=gs2,
                    ids = unsaved,
                    id.field = id,
                    column = match.field,
                    selected_file = selected_file,
                    ws = "FAFB")
      write_matches(gs=gs2,
                    ids = unsaved,
                    id.field = id,
                    column = quality.field,
                    selected_file = selected_file,
                    ws = "FAFB")
      write_matches(gs=gs2,
                    ids = unsaved,
                    id.field = id,
                    column = "note",
                    selected_file = selected_file,
                    ws = "FAFB")
      write_matches(gs=gs2,
                    ids = unsaved,
                    id.field = id,
                    column = "User",
                    selected_file = selected_file,
                    ws = "FAFB")
      saved = c(unsaved, saved)
      unsaved = c()
    }
    match.more = hemibrain_choice("Match more neurons? ")
  }
  say_encouragement(initials)
}

# Hidden
neuron_match_scanner <- function(brain,
                                 selected,
                                 id,
                                 chosen.field,
                                 nblast,
                                 threshold,
                                 batch_size,
                                 targets,
                                 targets.repository = c("CATMAID","flywire","hemibrain","lm"),
                                 query,
                                 query.repository = c("CATMAID","flywire","hemibrain","lm"),
                                 extra.neurons = NULL,
                                 extra.repository = c("none","CATMAID","flywire","hemibrain","lm"),
                                 match.field,
                                 quality.field,
                                 unsaved = c(),
                                 saved = c(),
                                 soma.size = 400,
                                 show.columns = c("cell.type","ItoLee_Hemilineage","note")){
  targets.repository = match.arg(targets.repository)
  extra.repository = match.arg(extra.repository)
  query.repository = match.arg(query.repository)
  check = unique(setdiff(unique(selected[[id]]),c(unsaved,saved)))
  check = id_okay(check)
  message("We'll look at ", length(check)," ", query.repository, " neurons sequentially.")
  for(i in 1:length(check)){
    # Get id
    message("neuron query ",i+length(saved),"/",length(check)+length(saved))
    n = as.character(check[i])
    end = n==selected[[id]][length(selected[[id]])]
    # Read top 10  matches
    r = tryCatch(sort(nblast[n,],decreasing = TRUE), error = function(e) NULL)
    if(is.null(r)){
      message(n, " not in NBLAST matrix, skipping ...")
      progress = readline(prompt = "Press any key to continue ")
      next
    }
    if(!is.null(threshold)){
      r = r[r>threshold]
      if(!length(r)){
        message(" no normalised NBLAST score greater or equal to ", threshold," for neuron ", n," ...")
        progress = readline(prompt = "This neuron will be skipped. Press any key to continue ")
        next
      }
    }
    batch.size = ifelse(length(r)>=batch_size,batch_size, length(r))
    # Plot brain
    rgl::clear3d()
    rgl::rgl.viewpoint(userMatrix = structure(c(0.990777730941772, 0.049733679741621,
                             -0.126039981842041, 0, 0.060652956366539, -0.994590044021606,
                             0.084330290555954, 0, -0.121164083480835, -0.091197244822979,
                             -0.988434314727783, 0, 0, 0, 0, 1), .Dim = c(4L, 4L)), zoom = 0.644609212875366) # FAFB14 view
    rgl::bg3d("white")
    plot3d(brain, alpha = 0.1, col ="grey")
    # Get data
    query.n = tryCatch(query[n], error = function(e){
      message("Could not immediately load query neuron: ", n)
      NULL
    })
    if(is.null(query.n)){ # in FAFB14 space.
      query.n = tryCatch({
        message("Neuron not found on Google drive, attempting to read ...")
        if(!requireNamespace("fafbseg", quietly = TRUE)) {
          stop("Please install fafbseg using:\n", call. = FALSE,
               "remotes::install_github('natverse/fafbseg')")
        }
        if(query.repository == "flywire"){
          fafbseg::choose_segmentation("flywire")
          query.n = fafbseg::skeletor(n)
        }else if(query.repository == "hemibrain"){
          query.n  = neuprintr::neuprint_read_neurons(n, all_segments = TRUE, heal = FALSE)
          query.n = scale_neurons.neuronlist(query.n, scaling = (8/1000))
          query.n = suppressWarnings(nat.templatebrains::xform_brain(query.n, reference = "FAFB14", sample = "JRCFIB2018F"))
        }else if (query.repository=="CATMAID"){
          query.n = catmaid::read.neurons.catmaid(query.n)
        }else{
          NULL
        }
      }, error = function(e) {NULL})
    }
    # Other neurons to always plot
    if(extra.repository!="none"){
      if(extra.repository=="CATMAID"){
        sk = selected[n,]$skid[1]
        if(!is.na(sk)){
          extra.n = tryCatch(catmaid::read.neurons.catmaid(sk, OmitFailures = TRUE), error = function(e) NULL)
        }else{
          extra.n = NULL
        }
      }else if(extra.repository=="flywire"){
        fw.id = selected[n,]$flywire.id[1]
        if(!is.na(fw.id)){
          extra.n = tryCatch(flywire_neurons()[as.character(fw.id)], error = function(e) NULL)
        }else{
          extra.n = NULL
        }
      }else{
        extra.n = NULL
      }
    }else{
      extra.n = NULL
    }
    if(!is.null(extra.neurons)){
      another.n = tryCatch(extra.neurons[n], error = function(e){
        NULL
      })
      if(is.null(another.n)){
        fw.id = selected[n,]$flywire.id[1]
        extra.n = tryCatch(flywire_neurons()[as.character(fw.id)], error = function(e) NULL)
      }
    }else{
      another.n = NULL
    }
    ### Plot in 3D
    if(!length(extra.n)){
      extra.n=NULL
    }
    if(!length(another.n)){
      extra.n=NULL
    }
    if(!is.null(query.n)){plot3d(query.n, lwd = 3, soma = soma.size, col = "#1BB6AF")}
    if(!is.null(extra.n)){plot3d(extra.n, lwd = 2, soma = soma.size, col = "black")}
    if(!is.null(another.n)){plot3d(another.n, lwd = 3, soma = soma.size, col = "grey50")}
    message("ID: ", n)
    show.columns = intersect(show.columns,colnames(query.n[,]))
    for(sc in show.columns){
      message(sc," : ", query.n[n,sc])
    }
    # Read database neurons
    message(sprintf("Reading the top %s %s hits",batch.size, targets.repository))
    batch = names(r)[1:batch.size]
    if(is.null(targets)){
      if(targets.repository=="flywire"){
        fafbseg::choose_segmentation("flywire")
        native  = fafbseg::skeletor(batch, mesh3d = FALSE, clean = FALSE)
      }else if (targets.repository == "hemibrain"){
        native  = neuprintr::neuprint_read_neurons(batch, all_segments = TRUE, heal = FALSE)
        native = scale_neurons.neuronlist(native, scaling = (8/1000))
        native = suppressWarnings(nat.templatebrains::xform_brain(native, reference = "FAFB14", sample = "JRCFIB2018F"))
      }else if (targets.repository == "CATMAID"){
        native  = catmaid::read.neurons.catmaid(batch,  OmitFailures = TRUE)
      }
    } else {
      batch.in = intersect(batch, names(targets))
      native = tryCatch(targets[match(batch.in,names(targets))], error = function(e) NULL)
      if(is.null(native)|length(batch.in)!=length(batch)){
        message("Dropping ",length(batch)-length(batch.in) ," neuron missing from targets" )
        batch = intersect(batch, batch.in)
      }
    }
    sel = c("go","for","it")
    k = 1
    j = batch.size
    # Cycle through potential matches
    while(length(sel)>1){
      sel = sel.orig = tryCatch(nat::nlscan(native[names(r)[1:j]], col = "#EE4244", lwd = 3, soma = soma.size),
                                error = function(e) NULL)
      if(is.null(sel)){
        next
      }
      if(length(sel)>1){
        message("Note: You selected more than one neuron")
      }
      if(length(sel) > 0){
        rgl::plot3d(native[sel], lwd = 2, soma = soma.size, col = hemibrain_bright_colour_ramp(length(sel)))
      }
      prog = hemibrain_choice(sprintf("You selected %s neurons. Are you happy with that? ",length(sel)))
      if(length(sel)>0){
        nat::npop3d()
      }
      if(!prog){
        sel = c("go","for","it")
        if(batch.size < length(r)){
          prog = hemibrain_choice(sprintf("Do you want to read %s more neurons? ", batch.size))
          if(prog){
            k = j
            j = j + batch_size
            if(!is.null(targets)){
              native2 = tryCatch(targets[(names(r)[(k+1):j])], error = function(e) {
                warning("Cannot read neuron: ", n, " from local targets, fetching from remote!")
                NULL
              })
            }
            if(is.null(targets)|is.null(native2)){
              if(targets.repository=="flywire"){
                fafbseg::choose_segmentation("flywire")
                native2  = fafbseg::skeletor((names(r)[1:batch.size]), mesh3d = FALSE, clean = FALSE)
              }else if (targets.repository == "hemibrain"){
                native2  = neuprintr::neuprint_read_neurons((names(r)[1:batch.size]), all_segments = TRUE, heal = FALSE)
                native = scale_neurons.neuronlist(native2, scaling = (8/1000))
                native2 = suppressWarnings(nat.templatebrains::xform_brain(native2, reference = "FAFB14", sample = "JRCFIB2018F"))
              }else if (targets.repository == "CATMAID"){
                native2  = catmaid::read.neurons.catmaid((names(r)[1:batch.size]), .progress = TRUE, OmitFailures = TRUE)
              }
            }
            native = nat::union(native, native2)
          }
        }
      }else{
        while(length(sel)>1){
          message("Choose single best match: ")
          sel = nat::nlscan(native[as.character(sel.orig)], col = hemibrain_bright_colours["orange"], lwd = 2, soma = TRUE)
          message(sprintf("You selected %s neurons", length(sel)))
          if(!length(sel)){
            noselection = hemibrain_choice("You selected no neurons. Are you happy with that? ")
            if(!noselection){
              sel = sel.orig
            }
          }
        }
      }
    }
    # Assign match and its quality
    if(length(sel)){
      sel = as.character(sel)
      if(!is.na(native[sel,chosen.field])){
        hit = as.character(native[sel,chosen.field])
      }else if(targets.repository=="flywire"){
        fixed = flywire_basics(native[sel])
        hit = as.character(fixed[,chosen.field])
      }else{
        hit = names(targets[sel])
      }
    }else{
      hit = "none"
    }
    message("You chose: ", hit)
    selected[selected[[id]]%in%n,match.field] = hit
    if(length(sel)){
      rgl::plot3d(native[sel],col= hemibrain_bright_colours["navy"],lwd=2,soma=TRUE)
      quality = must_be("What is the quality of this match? good(e)/okay(o)/poor(p)/tract-only(t) ", answers = c("e","o","p","t"))
    }else{
      quality = "n"
    }
    quality = standardise_quality(quality)
    selected[selected[[id]]%in%n,quality.field] = quality
    # Make a note?
    orig.note = selected[selected[[id]]%in%n,'note']
    if(!is.issue(orig.note)){
      message("This neuron has note: ", orig.note)
    }
    make.note = hemibrain_choice("Would you like to record a note? y/n ")
    while(make.note){
      note = readline(prompt = "Your note on this match/these neurons:  ")
      message(note)
      note[note%in%c(" ","","NA")] = NA
      selected[selected[[id]]%in%n,'note'] = note
      make.note = !hemibrain_choice("Happy with this note? y/n ")
    }
    unsaved = unique(c(unsaved, n))
    message(length(unsaved), " unsaved matches")
    show.columns = intersect(show.columns,colnames(selected))
    print(knitr::kable(selected[unsaved,c(id,show.columns,match.field,quality.field)]))
    p = must_be("Continue (enter) or save (s)? ", answers = c("","s"))
    if(p=="s"|end){
      break
    }
  }
  list(selected = selected, unsaved = unsaved)
}







