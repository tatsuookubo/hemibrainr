# Gooogle drive based utilities

# google upload neuronlistfh
## x is a neuronlist or a path to folder with saved neuronlistfh
googledrive_upload_neuronlistfh <- function(x,
                                            clean = FALSE,
                                            team_drive = hemibrainr_team_drive(),
                                            file_name = "neurons.rds",
                                            folder = "flywire_neurons",
                                            subfolder = NULL,
                                            WriteObjects = c("missing","yes"),
                                            numCores = 1){
  # don't exhaust rate limit
  WriteObjects = match.arg(WriteObjects)
  numCores = ifelse(numCores>10,10,numCores)

  # Get drive
  td = googledrive::team_drive_get(team_drive)
  drive_td = googledrive::drive_find(type = "folder", team_drive = td)
  gfolder= subset(drive_td,drive_td$name==folder)[1,]
  if(!is.null(subfolder)){
    sub = googledrive::drive_ls(path = gfolder, type = "folder", team_drive = td)
    gfolder = subset(sub, sub$name ==subfolder )[1,]
  }
  sub = googledrive::drive_ls(path = gfolder, team_drive = td)

  # Get data folder
  t.folder.data = googledrive::drive_ls(path = gfolder, type = "folder", team_drive = td)
  t.folder.data = subset(t.folder.data, t.folder.data$name == "data")[1,]
  if(is.na(t.folder.data$name)){
    googledrive::drive_mkdir(name = "data",
                             path = gfolder,
                             overwrite = TRUE)
    t.folder.data = googledrive::drive_ls(path = gfolder, type = "folder", team_drive = td)
    t.folder.data = subset(t.folder.data, t.folder.data$name == "data")[1,]
  }

  # Save locally
  if(nat::is.neuronlist(x)){
    temp = tempfile()
    temp.data = file.path(temp,"data")
    dir.create(temp.data)
    on.exit(unlink(temp, recursive=TRUE))
    temp.rds = paste0(temp,"/",file_name)
    nl = nat::as.neuronlistfh(x, dbdir= temp.data, WriteObjects = "yes")
    nat::write.neuronlistfh(nl, file= temp.rds, overwrite=TRUE)
    local.path = NULL
  }else{
    temp.data = file.path(x,"data")
    temp.rds = list.files(x, pattern = ".rds$", full.names =TRUE)
    message("data folder: ", temp.data)
    message(".rds files: ", paste(temp.rds,collapse=", "))
    local.path = x
  }

  # upload
  t.list.master = list.files(temp.data,full.names = TRUE)
  error.files = upload = c()
  if(WriteObjects=="missing"){
    sub.data = googledrive::drive_ls(path = t.folder.data, team_drive = td)
    t.list.master = t.list.master[! basename(t.list.master) %in% sub.data$name]
  }
  if(length(t.list.master)){
    if(numCores>1){
      batch = 1
      batches = split(t.list.master, round(seq(from = 1, to = numCores, length.out = length(t.list.master))))
      foreach.upload <- foreach::foreach (batch = 1:length(batches)) %dopar% {
        t.list = batches[[batch]]
        for(t.neuron.fh.data.file in t.list){
          t = basename(t.neuron.fh.data.file)
          save.data =  t.folder.data
          upload = tryCatch({gsheet_manipulation(googledrive::drive_upload,
                                                 media = t.neuron.fh.data.file,
                                                 path = save.data,
                                                 verbose = FALSE)},
                            error = function(e){
                              cat(as.character(e))
                              error.files <<- c(error.files,t.neuron.fh.data.file)
                              NA
                            } )
        }
      }
    }else{
      pb <- progress::progress_bar$new(
        format = "  uploading [:bar] :current/:total eta: :eta",
        total = length(t.list.master), clear = FALSE, show_after = 1)
      for(t.neuron.fh.data.file in t.list.master){
        pb$tick()
        t = basename(t.neuron.fh.data.file)
        save.data =  t.folder.data
        upload = tryCatch({gsheet_manipulation(googledrive::drive_upload,
                                               media = t.neuron.fh.data.file,
                                               path = save.data,
                                               verbose = FALSE)},
                          error = function(e){
                            cat(as.character(e))
                            error.files <<- c(error.files,t.neuron.fh.data.file)
                            NA
                          } )
      }
    }
    if(length(error.files)){
      warning("Failed to upload: ", length(error.files)," files")
    }
  }

  # upload .rds
  for(rds in temp.rds){
    file_name = basename(rds)
    gfile = subset(sub, sub$name == file_name )
    if(nrow(gfile)){
      save.position = googledrive::as_id(gfile[1,]$id)
    }else{
      save.position = gfolder
    }
    google_drive_place(media = rds,
                       path = save.position,
                       verbose = TRUE)
  }

  # Clean
  if(clean){
    message("Deleting unused file hash files for neurons ...")
    googledrive_clean_neuronlistfh(local.path = local.path,
                                   team_drive = hemibrainr_team_drive(),
                                   folder = folder,
                                   subfolder = subfolder)
  }
}

# Google drive
google_drive_place <- function(media,
                               path,
                               verbose = TRUE,
                               check = TRUE,
                               ...){
  # If path is folder, check contents to duplicates
  if(check){
    f = tryCatch(googledrive::is_folder(path), error = function(e) FALSE)
    if(f){
      ls = googledrive::drive_ls(path, ...)
      p = subset(ls, ls$name == basename(media))$id
      if(length(p)){
        path = googledrive::as_id(p[1])
      }
    }else{
      path = googledrive::as_id(path)
    }
  }
  if("drive_id"%in%class(path)){
    googledrive::drive_update(media = media,
                              file = path,
                              verbose = verbose,
                              ...)
  }else{
    googledrive::drive_put(media = media,
                           path = path,
                           verbose = verbose,
                           ...)
  }
}

# Remove unused filehash files
googledrive_clean_neuronlistfh <- function(team_drive = hemibrainr_team_drive(),
                                           local.path = NULL,
                                           folder = NULL,
                                           subfolder = NULL){
  # don't exhaust rate limit
  numCores = ifelse(numCores>10,10,numCores)
  if(!is.null(local.path)&is.null(subfolder)){
    stop("Either specify a subfolder on the ", team_drive, ' drive to clean,
         which matches the given local path, or set loca.path to NULL
         and attemot to clean the whole drive/folder on drive')
  }
  if(!is.null(local.path)&is.null(folder)&is.null(subfolder)){
    stop("A folder (e.g. flywire_neurons) and a
         subfolder (for brainspace, e.g. FCWB) must be given
         that match your local.path: ", local.path)
  }

  # Save .rds files locally, and find excess filehash
  find_excess <- function(sub,
                          local.path = NULL,
                          team_drive = NULL){
    temp = tempfile()
    temp.data = paste0(temp,"/RDS/")
    dir.create(temp.data, recursive = TRUE)
    on.exit(unlink(temp, recursive=TRUE))
    remove = googledrive::as_dribble()
    if(sum(grepl("rds$",sub$name))>1){
      fsub = subset(sub, grepl("rds$",sub$name))
      fdata = subset(sub, grepl("data$",sub$name))[1,]
      all.keys = c()
      if(is.null(local.path)){
        for(file in fsub$id){
          fnam = subset(fsub, fsub$id==file)$name
          path = paste0(temp.data,fnam)
          googledrive::drive_download(file = googledrive::as_id(file),
                                      path = path,
                                      overwrite = TRUE,
                                      verbose = FALSE)
          a = readRDS(path)
          b = attributes(a)
          keys = b$keyfilemap
          all.keys = c(all.keys,keys)
        }
      }else{
        files = list.files(local.path, pattern  = ".rds$",  full.names = TRUE)
        for(file in files){
          a = readRDS(file)
          b = attributes(a)
          keys = b$keyfilemap
          all.keys = c(all.keys,keys)
        }
      }
      data = googledrive::drive_ls(path = googledrive::as_id(fdata$id), team_drive = team_drive)
      data = data[!grepl("\\.",data$name),]
      delete = data[!data$name%in%all.keys,]
      remove = rbind(remove, delete)
      message("Cleaning out ", nrow(remove), " files")
    }
    remove = remove[!duplicated(remove$id),]
    remove
  }

  # Get drive
  td = googledrive::team_drive_get(team_drive)
  drive_td = googledrive::drive_find(type = "folder", team_drive = td)
  if(!is.null(folder)){
    gfolder= subset(drive_td,drive_td$name==folder)[1,]
    if(!is.null(subfolder)){
      sub = googledrive::drive_ls(path = gfolder, type = "folder", team_drive = td)
      gfolder = subset(sub, sub$name ==subfolder )[1,]
    }
    drive_td = googledrive::drive_ls(path = gfolder, team_drive = td)
  }

  # Find files to delete
  message("Searching for files we might want to remove ...")
  if(is.null(local.path)&is.null(subfolder)){
    # Iterate to find .rds files
    remove = googledrive::as_dribble()
    for(folder in drive_td$id){
      sub = googledrive::drive_ls(path = googledrive::as_id(folder), type = "folder", team_drive = td)
      if("data" %in% sub$name){
        sub = googledrive::drive_ls(path = googledrive::as_id(folder), team_drive = td)
        remove = rbind(remove, find_excess(sub,
                                           local.path = NULL,
                                           team_drive = td))
      }
    }
  }else{
    remove = find_excess(drive_td,
                         local.path = local.path,
                         team_drive = td)
  }

  # rm
  if(nrow(remove)){
    pb <- progress::progress_bar$new(
        format = "  deleting [:bar] :current/:total eta: :eta",
        total = length(remove$id), clear = FALSE, show_after = 1)
    for(r in remove$id){
        pb$tick()
        e = tryCatch(googledrive::drive_rm(googledrive::as_id(r), verbose = FALSE),
                     error = function(e){
                       cat(as.character(e))
                       NULL
                     } )
    }
  }
}

# upload nblast matrix
googledrive_upload_nblast<- function(x,
                                     team_drive = hemibrainr_team_drive(),
                                     folder = "hemibrain_nblast",
                                     subfolder = NULL,
                                     file = NULL,
                                     threshold=-0.5,
                                     digits=3,
                                     format=c("rda", "rds"),
                                     ...){
  format=match.arg(format)

  # Get drive
  td = googledrive::team_drive_get(team_drive)
  drive_td = googledrive::drive_find(type = "folder", team_drive = td)
  gfolder= subset(drive_td,drive_td$name==folder)[1,]
  if(!is.null(subfolder)){
    sub = googledrive::drive_ls(path = gfolder, type = "folder", team_drive = td)
    gfolder = subset(sub, sub$name ==subfolder )[1,]
  }

  # Compress
  objname=deparse(substitute(x))
  colnames(x) = gsub("_m$","",colnames(x)) # factor in mirrored neurons
  rownames(x) = gsub("_m$","",rownames(x))
  x = tryCatch(apply(x, 2, function(i) tapply(x, rownames(x), sum, na.rm = TRUE)), error = function(e) x)
  x = tryCatch(t(apply(t(x), 2, function(i) tapply(i, colnames(x), sum, na.rm = TRUE))), error = function(e) x)
  x[x<threshold]=threshold
  x=round(x, digits=digits)

  # Save in temporary location
  newobjname <- paste0(objname, ".compressed")
  temp <- tempfile()
  on.exit(unlink(temp, recursive=TRUE))
  fname <- paste0(temp, "/",paste0(file, newobjname), ".", format)
  if(format=="rds") {
    saveRDS(x, file=fname, ...)
  } else {
    message(newobjname)
    assign(newobjname, x)
    save(list = newobjname, file = fname, ...)
  }

  # Does the file already exist?
  file_name = basename(fname)
  sub = googledrive::drive_ls(path = gfolder, team_drive = td)
  gfile = subset(sub, sub$name ==file_name)
  if(nrow(gfile)){
    save.position = googledrive::as_id(gfile[1,]$id)
  }else{
    save.position = gfolder
  }

  # Upload
  google_drive_place(media = fname,
                     path = save.position,
                     verbose = TRUE)
}

# hidden
gsheet_manipulation <- function(FUN,
                                ...,
                                wait = 10,
                                max.tries = 25,
                                return = FALSE){
  sleep = wait
  success = FALSE
  tries = 0
  while(!success){
    g = tryCatch(FUN(...),
                 error = function(e){
                   cat(as.character(e))
                   return(NULL)
                 })
    if(!is.null(g)){
      success = TRUE
    }else{
      tries = tries+1
      if(tries>max.tries){
        stop("Could not make google manipulation")
      }
      message("Google read/write failure(s), re-trying in ", sleep," seconds ...")
      Sys.sleep(sleep)
      sleep = sleep + wait
      if(sleep > 600){
        slep <- 600
      }
    }
  }
  if(return){
    if(is.data.frame(g)){
      g = unlist_df(g)
    }
    return(g)
  }
}

# hidden
paste_coords <- function(xyz){
  paste0("(",paste(xyz,sep=",",collapse=","),")")
}

# write columns to gsheet
gsheet_update_cols <- function(write.cols,
                                gs,
                                selected_sheet,
                                sheet = NULL,
                                ...
                       ){
  shared = setdiff(write.cols,colnames(write.cols))
  if(!length(shared)){
    stop("write.cols missing from given data frame, gs")
  }
  if(!nrow(gs)){
    stop("No rows in given data frame, gs")
  }
  for(wc in write.cols){
    index = match(wc,colnames(gs))
    if(index>26){
      letter = paste0("A",LETTERS[match(wc,colnames(gs))-26])
    }else if(index>52){
      letter = paste0("B",LETTERS[match(wc,colnames(gs))-52])
    }else{
      letter = LETTERS[match(wc,colnames(gs))]
    }
    range = paste0(letter,1,":",letter,nrow(gs)+1)
    update = tryCatch(as.data.frame(nullToNA(gs[,wc]), stringsAsFactors = FALSE),
                      error = function(e) data.frame(rep(NA,nrow(gs)), stringsAsFactors = FALSE))
    colnames(update) = wc
    gsheet_manipulation(FUN = googlesheets4::range_write,
                                     ss = selected_sheet,
                                     range = range,
                                     data = update,
                                     sheet = sheet,
                                     col_names = TRUE,
                                     ...)
  }
}



