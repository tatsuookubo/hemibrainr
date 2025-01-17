% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/hemibrain_standardise.R
\name{standard_transmitters}
\alias{standard_transmitters}
\alias{standard_statuses}
\alias{standard_lineages}
\alias{standard_compartments}
\alias{standardise}
\title{Use standard names and spellings}
\usage{
standard_transmitters(x)

standard_statuses(x, invert = FALSE)

standard_lineages(x)

standard_compartments(x, invert = FALSE)

standardise(x)
}
\arguments{
\item{x}{a character vector to be standardised.}

\item{invert}{return compartment numbers rather than names.}
}
\value{
a character vector
}
\description{
Standardise the names of lineage groups, neuron compartments and transmitters.
}
