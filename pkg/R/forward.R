# Function to compute forward simulation of community dynamics with (eventually)
# environmental filtering
forward <- function(initial, prob = 0, d = 1, gens = 150, keep = FALSE,
                    pool = NULL, traits = NULL, filt = NULL, limit.sim = FALSE, 
                    coeff.lim.sim = 1, type.filt = "immig", type.limit = "death",
                    sigm = 0.1, add = F, var.add = NULL, prob.death = NULL,
                    method.dist = "euclidean", plot_gens = FALSE) {
  # The function will stop if niche - based dynamics is requested, but trait
  # information is missing in the local community
  # For strictly neutral communities, a vector of species names is enough for
  # the initial community
  
  # Checking basic parameters
  
  if (!is.numeric(prob) | prob < 0) {
    stop("Probability of migration or mutation must be a number belonging to ",
         "[0; 1] interval.")
  }
  
  if (!is.numeric(d) | d < 0) {
    stop("Number of individuals that die in each time step must be a positive",
         " number.")
  }
  
  if (!is.numeric(gens) | gens <= 0) {
    stop("Number of generations must be a positive number.")
  }
  
  if (!is.logical(keep)) {
    stop("keep parameter must be a boolean.")
  }
  
  if (!is.logical(limit.sim)) {
    stop("limiting similarity parameter must be a boolean.")
  }
  
  if (!is.numeric(coeff.lim.sim)) {
    stop("coeff.lim.sim parameter must be numeric.")
  }
  
  if (!is.null(filt) & (is.null(type.filt) | !any(type.filt%in%c("immig","death","loc.recr"))))
    stop("Type of environmental filtering should be immig, death and/or loc.recr")
  
  if (limit.sim & (is.null(type.limit) | !any(type.limit%in%c("immig","death","loc.recr"))))
    stop("Type of limiting similarity should be immig, death and/or loc.recr")
  
  if (!is.numeric(sigm) | sigm < 0) {
    stop("sigm parameter must be a positive number.")
  }
  
  if (!is.null(filt) & !is.function(filt)) {
    stop("filt() must be a function.")
  }    
  
  if((add & is.null(var.add)) | (!add & !is.null(var.add))) 
    warning("No additional variables are passed to filt")
  
  if ((method.dist %in% c("euclidean", "maximum", "manhattan", "canberra",
                          "binary", "minkowski")) == FALSE) {
    stop("Provided distance does not exist. See stats::dist function for help.")
  }
  
  if (!is.logical(plot_gens)) {
    stop("plot_gens parameter must be a boolean.")
  }
  
  # Stops if only a vector of species name is given as initial community with
  # environmental filtering or limiting similarity
  if ((is.character(initial) | is.vector(initial)) &
      (limit.sim | !is.null(filt))) {
    stop("Trait information must be provided along with species identity in",
         " the initial community for niche - based dynamics")
  }
  
  # If environmental filtering or limiting similarity, the initial community
  # needs to be a matrix or a data.frame
  if (!is.matrix(initial) & !is.data.frame(initial) &
      (limit.sim | !is.null(filt))) {
    stop("Misdefined initial community")
  }
  
  # If no limiting similarity nor environmental filter -> community dynamics are
  # considered neutral
  if (!limit.sim & is.null(filt)) {
    message("Simulation of a neutral community")
  }
  
  # "pool" will be a three - column matrix of individuals in the regional pool,
  # with individual id in first column, species name in second column, and
  # additional trait information for niche - based dynamics in third column
  if (is.character(pool)) {
    pool <- data.frame(id = 1:length(pool),
                       sp = pool,
                       trait = rep(NA, length(pool)),
                       stringsAsFactors = FALSE)
    
    if (limit.sim | !is.null(filt)) {
      message("No trait information provided in the regional pool")
      pool[, 3] <- runif(nrow(pool))
      message("Random trait values attributed to individuals of the regional",
              " pool")
      colnames(pool) <- c("id", "sp", "trait")
    }
  }
  
  # If species pool is specified by user
  if (!is.null(pool)) {
    if(ncol(pool)==2 &  !is.null(traits)) {
      # Assign trait values to individuals of the pool
      pool[,3:(2+ncol(traits))] <- traits[pool[,2],]
      if(any(is.na(pool[,-(1:2)]))) 
        stop("Mismatch of species names between pool and traits")
    }
    if (ncol(pool) < 2) {
      stop("The regional pool is misdefined (at least two columns ",
           "required when a matrix or data frame is provided)")
    } else if (ncol(pool) == 2) {
      message("No trait information provided in the regional pool")
    }
    if (limit.sim | !is.null(filt)) {
      if(!is.null(traits)) {
        # TOSOLVE: pb if several traits in traits
        pool[, 3] <- traits[pool[,2],]
      }
      if(is.null(traits) & ncol(pool) < 3) {
        pool[, 3] <- runif(nrow(pool))
        
        message("Random (uniform) trait values attributed to individuals of ",
                "the regional pool")
      }
    }
    # TEMPORARY - TOUPDATE
    if(ncol(pool) == 3) colnames(pool) <- c("id", "sp", "trait")
    if(ncol(pool) == 2) colnames(pool) <- c("id", "sp")
  }
  
  if (is.null(traits) & (is.null(pool) | NCOL(pool) < 3)) {
    warning("No trait information provided in the regional pool")
  }
  
  if (!is.null(traits) & is.null(colnames(traits))) {
    colnames(traits) <- paste("tra", 1:ncol(traits), sep = "")
  }
  if (!is.null(pool) & is.null(colnames(pool))) {
    if (ncol(pool) > 2) {
      colnames(pool) <- c("ind", "sp", paste("tra", 1:(ncol(pool) - 2),
                                             sep = ""))
    }
  }
  
  # "init_comm" is a 3 columns matrix of individuals in the initial community,
  # with individual id in first column, species name in second column, and
  # additional trait information for niche-based dynamics in the third column
  if (is.character(initial)) {  # If only list of species names provided
    # The ids of individuals present in the initial community begi with "init"
    J <- length(initial)
    if(is.null(traits)) {
      init_comm <- data.frame(id = paste("init", 1:J, sep = ""),
                              sp = initial,
                              trait = rep(NA, J),
                              stringsAsFactors = FALSE) 
    } else {
      init_comm <- data.frame(id = paste("init", 1:J, sep = ""),
                              sp = initial,
                              trait = traits[initial,],
                              stringsAsFactors = FALSE) 
    }
  } else {
    J <- nrow(initial)
    if (ncol(initial) == 2 & is.null(traits)) {
      message("Two-column initial community: assumed to represent species ",
              "and trait information; individual ids will be generated")
      init_comm <- data.frame(id = paste("init", 1:J, sep = ""),
                              sp = initial[, 1],
                              trait = initial[, 2],
                              stringsAsFactors = FALSE)
    } else if (ncol(initial) == 2 & !is.null(traits)) {
      message("Two-column initial community: assumed to represent individual ",
              "and species ids; trait information in traits")
      init_comm <- data.frame(initial,
                              trait = traits[initial[,2], ],
                              stringsAsFactors = FALSE)
    } else if (ncol(initial) > 2) {
      init_comm <- initial
    }
  }
  
  if(is.null(filt) & !is.null(pool)) if(ncol(pool)==2 & ncol(init_comm)>2)
  {
    # TO BE IMPROVED
    # No need to keep trait information for neutral dynamics
    init_comm <- init_comm[,1:2]
  }
  
  if (J < d) stop("The number of dead individuals per time step ",
		  "cannot be greater than community size")
	  
  if ((limit.sim | !is.null(filt))) if(any(is.na(init_comm[, 3]))) {
    stop("Trait information must be provided in initial community ",
         "composition for niche-based dynamics")
  }
  
  # TODO: possibility to handle several traits
  if(ncol(init_comm)==3) colnames(init_comm) <- c("id", "sp", "trait")
  if(ncol(init_comm)==2) colnames(init_comm) <- c("id", "sp")
  
    new.index <- 0
  
  ## Forward simulation with community
  
  # Begins with the initial community
  next_comm <- init_comm
  
  # Richness of initial community is not included
  sp_t <- c()
  
  ind_t <- c()	
  dist.t <- c()
  
  if (keep) {  # If the user asked to keep all the communities at each timestep
    comm_through_time <- c()
  }
  
  # Simulate the community for the given number of generations
  for (i in 1:gens) {
    if (keep) {
      # Store the community at time i
      comm_through_time[[i]] <- next_comm
    }  
    
    # Simulate community dynamics
    next_comm <- pick(next_comm, d = d, prob = prob, pool = pool,
                      prob.death = prob.death, filt = filt, 
                      limit.sim = limit.sim, coeff.lim.sim = coeff.lim.sim, 
                      type.filt = type.filt, type.limit = type.limit, 
                      sigm = sigm, new.index = new.index,
                      method.dist = "euclidean")
    
    sp_t <- c(sp_t, length(unique(next_comm$com$sp)))
    ind_t <- c(ind_t, length(unique(next_comm$com$ind)))
    
    # Store average trait distance among coexisting individuals
    if (limit.sim) {
      dist.t <- c(dist.t, next_comm$dist.t)
    }
    new.index <- next_comm$new.index
    next_comm <- next_comm$com
  }
  
  if (plot_gens) { # Plotting number of individuals and species over generations
    
    uniq_df <- data.frame(gens = 1:gens, ind_t = ind_t, sp_t = sp_t,
                          stringsAsFactors = FALSE)
    
    if (requireNamespace("ggplot2", quietly = TRUE)) {
      
      # Plot the number of individuals through all the generations
      plot_individuals <- ggplot(uniq_df, aes_string("gens", "ind_t")) +
        geom_line() +
        geom_line(aes_string("gens", "ind_t"),
                  size = 1) +
        labs(x = "Number of generations",
             y = "Number of distinct ancestors")
      
      # Plot the number of species through all the generations
      plot_species <- ggplot(uniq_df,
                             aes_string("gens", "sp_t")) +
        geom_line(size = 1) +
        labs(x = "Number of generations",
             y = "Number of species")
      
      print(plot_individuals)
      print(plot_species)
    }
  }
  
  if (limit.sim)
  {
    if (keep) return(list(com_t = comm_through_time,
                          sp_t = sp_t,
                          dist.t = dist.t,
                          pool = pool,
                          call = match.call()))
    else return(list(com = next_comm, sp_t = sp_t, 
                     dist.t = dist.t, pool = pool, call = match.call()))
  } else
  {
    if (keep) return(list(com_t = comm_through_time,
                          sp_t = sp_t,
                          pool = pool,
                          call = match.call()))
    else return(list(com = next_comm, sp_t = sp_t, pool = pool, call = match.call()))
  }
}

# Precise function to simulate a single timestep by picking an individual in
# the pool or make an individual mutate
pick <- function(com, d = 1, prob = 0, pool = NULL, prob.death = prob.death,
                 filt = NULL, limit.sim = NULL, coeff.lim.sim = 1, 
                 type.filt = "immig", type.limit = "death", sigm = 0.1,
                 new.index = new.index, method.dist = "euclidean") {
  
  
  if (is.null(pool)) {
    # If no species pool specified, mutate an individual
    return(pick.mutate(com,
                       d = d,
                       prob.of.mutate = prob,
                       new.index = new.index)) 
  
  } else {
	  
    if((!is.null(filt) | limit.sim) & prob > 0 & any(is.na(pool[,-(1:2)]))) {
	    stop("With environmental filtering, NA trait values not allowed in ",
	         "regional pool")
    }
	  
  # If there is a species pool make an individual immigrates
    return(pick.immigrate(com, d = d, prob.of.immigrate = prob, pool = pool,
                          prob.death = prob.death, filt = filt, 
                          limit.sim = limit.sim, coeff.lim.sim = coeff.lim.sim, 
                          type.filt = type.filt, type.limit = type.limit, 
                          sigm = sigm, method.dist = "euclidean"))
  }
}

# Return community with mutated inidividual (= new species)
pick.mutate <- function(com, d = 1, prob.of.mutate = 0, new.index = 0) {
  
  if (is.vector(com)) {
    # If community only defined by species names
    J <- length(com)
    
    com <- data.frame(id = paste("ind", 1:J, sep = ""),
                      sp = as.character(com),
                      trait = rep(NA, J),
                      stringsAsFactors = FALSE)
  
  } else if (is.matrix(com) | is.data.frame(com)) {
    # If the community has defined traits
    J <- nrow(com)
    
    if (is.matrix(com)) {
      	com <- as.data.frame(com, stringsAsFactors = FALSE)
 	com[, 1] <- as.character(com[, 1])
     	com[, 2] <- as.character(com[, 2])	  
    }
    
  } else {
    stop("pick.mutate: misdefined community composition")
  }
  
  ## Simulate the dynamics of the community
  
  # Number of individuals who die at this timestep
  died <- sample(J, d, replace = FALSE)
  
  # How many of the dead individuals are replaced by mutated individuals
  mutated <- runif(length(died)) < prob.of.mutate
  
  # Number of mutated individuals
  n_mutated <- sum(mutated)
  
  # Dead individuals who did not mutate
  dead_non_mutated <- sum(!mutated)
  
  # Replace dead non mutated individuals by individuals from other species
  com[died[!mutated], ] <- com[sample(1:nrow(com), dead_non_mutated,
                                      replace = TRUE), ]
  
  # When mutation occurs
  if (n_mutated > 0) {
    
    # Attribute new species to individuals who mutate
    com[died[mutated], 1:2] <- paste("new.sp", new.index + (1:n_mutated),
                                     sep = "")
    
    #com[died[mutated], 3] <- rep(NA, n_mutated)  # No trait values
    # Default = trait value drawn from uniform distribution between 0 and 1
    com[died[mutated], 3] <- runif(n_mutated)
	  
    # Number of new species which appeared (next one will be new.index + 1)
    new.index <- new.index + n_mutated
  }
  
  return(list(com = com, new.index = new.index))
}

# Function to return individuals who immigrated from the species pool
# limit.sim = distances de traits; filt = habitat filtering function
pick.immigrate <- function(com, d = 1, prob.of.immigrate = 0, pool,
                           prob.death = NULL, filt= NULL, limit.sim = NULL,
                           coeff.lim.sim = 1, type.filt = "immig", 
                           type.limit = "death", sigm = 0.1,
                           method.dist = "euclidean") {
  
  if (is.vector(com)) {
    # If community only defined by species names
    J <- length(com)
    
    com <- data.frame(id = paste("ind", 1:J, sep = ""),
                    sp = as.character(com),
                    trait = rep(NA, J),
                    stringsAsFactors = FALSE)
  
  } else if (is.matrix(com) | is.data.frame(com)) {
    # If the community has defined traits
    J <- nrow(com)
    
    if (is.matrix(com)) {
      com <- as.data.frame(com, stringsAsFactors = FALSE)
    }
    com[, 1] <- as.character(com[, 1])
    com[, 2] <- as.character(com[, 2])
      
  } else {
    stop("pick.immigrate: misdefined community composition")
  }
  
  # Function defining habitat filtering according to trait value
  if (!is.null(filt)) {
    hab_filter <- function(x) filt(x)
  } else {
    # If no function defined, dummy function returning value 1
	  hab_filter <- function(x) vapply(x, function(x) 1, c(1))
  }
  
  # Traits distances used to simulate limiting similarity
  if (limit.sim) {
   tr.dist <- as.matrix(dist(com[, -(1:2)], method = method.dist))
   colnames(tr.dist) <- com[, 1]
   rownames(tr.dist) <- com[, 1]
   diag(tr.dist) <- NA
   
   # dist.t will display the average trait distance among species
   # for the whole community at each generation
   if (min(dim(tr.dist))>1) {
     dist.t <- mean(tr.dist[com[, 1], com[, 1]], na.rm = TRUE)
   } else dist.t <- NA
   
  } else {
    tr.dist <- NULL
  }
					   
  # Initial community
  com.init <- com
  
  if (!limit.sim & is.null(filt)) {
    
    died <- sample(J, d, replace = FALSE)
    
    com <- com[-died, ]
    
    if (any(is.na(com[, 1]))) {
      stop("Error: NA values in community composition (1)")
      }
  
  } else {
    
    if(limit.sim)
    {
      # lim_sim_function indicates the influence of limiting similarity depending on
      # a Gaussian function of pairwise trait distances
      # coeff.lim.sim modulates the strength of limiting similarity
      lim_sim_function <- function(x) {
        coeff.lim.sim * (sum(exp( -x^2 / (2 * (sigm^2))), na.rm = TRUE))
      }
    }
    
    # Vector of the individual probability of dying
    if (is.null(prob.death)) {
      prob.death <- rep(1, nrow(com))
    }
    
    # Influence of limiting similarity on mortality
    if("death" %in% type.limit & limit.sim & !is.null(tr.dist))
    {
      # Under limiting similarity, mortality increases when an individual is more
      # similar to other resident individuals
      # For each species: compute death probability depending on limiting
      # similarity plus a baseline individual death probability
     
      prob.death <- apply(tr.dist[com[, 1], com[, 1]], 2,
                            function(x) lim_sim_function(x))
      # Add baseline probability
      prob.death <- prob.death + 1/J
      names(prob.death ) <- com[, 1]
    }
      
    # Influence of habitat filtering on mortality
    if("death" %in% type.filt & !is.null(filt))
    {
      if (any(is.na(hab_filter(com[, -(1:2)])))) {
         stop("Error: NA values in habitat filter")
      }
      
      prob.death <- prob.death * (1 - hab_filter(com[, -(1:2)]) /
                                      sum(hab_filter(com[, -(1:2)])))
    }
      
    # Giving names to prob.death
    names(prob.death) <- com[, 1]      
    
    # Position of dead individuals in prob.death vector
    died <- sample(J, d, replace = FALSE, prob = prob.death)
    com <- com[-died, ] 
    
    if (sum(is.na(com[, 1])) != 0) {
      stop("Error: NA values in community composition (2)")
    }
  } 
  
  immigrated <- runif(d) < prob.of.immigrate
  
  # If probability of immigration is high, then the new individual is drawn
  # from the regional pool
  J1 <- sum(immigrated)
  # The lower the probability of immigration, the higher the probability of
  # drawing the new individual from the community
  J2 <- sum(!immigrated)
  
  if (J1 > 0) { 
    # Immigrant drawn from regional pool
    
    # Default equal probability of immigration
    prob = rep(1, nrow(pool))
    
    # Influence of habitat filtering on immigration
    if ("immig" %in% type.filt & !is.null(filt)) {
      if (any(is.na(hab_filter(pool[, -(1:2)])))) {
        stop("Error: NA values in habitat filtering of immigrants")
      }
      
      prob <- prob * vapply(pool[, -(1:2)], hab_filter, 0)
    }
    
    # Influence of limiting similarity on immigration
    if("immig" %in% type.limit & limit.sim) {
      # Establishment success depends on how distant is the candidate from local individuals
      lim_sim_mig_function <- function(x) {
        coeff.lim.sim * (sum(exp( -(x-com.init[,-(1:2)])^2 / (2 * (sigm^2))), na.rm = TRUE))
      }
      
      # Influence of limiting similarity on establishment
      prob.estab <- sapply(pool[, -(1:2)],
                           function(x) lim_sim_mig_function(x))
      prob.estab <- prob.estab/max(prob.estab)
      prob.estab <- 1 - prob.estab
      # Add baseline probability
      prob.estab <- prob.estab + 1/J
      prob <- prob * prob.estab
    }
    
    # Add new immigrated individual to community
    com <- rbind(com, pool[sample(1:nrow(pool), J1, replace = TRUE,
                                  prob = prob),])
    
    if (any(is.na(com[, 1]))) {
      stop("Error: NA values in community composition (3)")
      }
  }
  
  if (J2 > 0) { # Recruitment from com.init
    
    # Default equal probability of recruitment of local offspring
    prob = rep(1, nrow(com.init))
    
    # Influence of habitat filtering on recruitment
    if("loc.recr" %in% type.filt & !is.null(filt)) {
      
      if (any(is.na(hab_filter(com.init[, -(1:2)])))) {
        stop("Error: NA values in habitat filtering of local offspring")
      }
        
      prob <- prob * vapply(com.init[, -(1:2)], hab_filter, 0)
    }
      
    # Influence of limiting similarity on recruitment
    if("loc.recr" %in% type.limit & limit.sim) {
      # Same constraint is used for local offspring and immigrants
      prob.estab <- prob.death/max(prob.death)
      prob.estab <- 1 - prob.estab
      # Add baseline probability
      prob.estab <- prob.estab + 1/J
      prob <- prob * prob.estab
    }
    
    # Add new established offspring individual to community
    com <- rbind(com, com.init[sample(1:nrow(com.init), J2, replace = TRUE,
                                  prob = prob),])
     
    if (any(is.na(com[, 1]))) {
      print(J2)
      stop("Error: NA values in community composition (4)")
    }
  }
    
  if (limit.sim) {
    # If there limiting similarity return the factor
    return(list(com = com, dist.t = dist.t))
  
  } else {
    # Without limiting similarity
    return(list(com = com))
  
  }
}


