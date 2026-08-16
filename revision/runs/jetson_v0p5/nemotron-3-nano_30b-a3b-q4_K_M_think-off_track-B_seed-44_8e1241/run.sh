#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

process_sample() {
    local sample=$1
    local r1="data/raw/${sample}_1.fq.gz"
    local r2="data/raw/${sample}_2.fq.gz"
    local base="results/${sample}"

    # Skip if all outputs exist
    [ -f "${base}.bam" ] && return

    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 4 -b - > "${base}.bam"
    samtools sort -@ 4 -o "${base}.sorted.bam" "${base}.bam"
    samtools index -@ 4 "${base}.sorted.bam"

    # lofreq pre-processing
    samtools mpileup -f data/ref/chrM.fa -t DP,AD,SP -l <(samtools depth -aa "${base}.sorted.bam" | cut -f1) \
        --bq 20 --strand bias --min-MQ 30 --min-BQ 15 \
        -o "${base}.mpileup"

    lofreq call-ac > "${base}.lofreq.vcf.gz"
    bgzip -@ 4 -c "${base}.lofreq.vcf.gz" > "${base}.vcf.gz"
    tabix -p vcf "${base}.vcf.gz"

    # bcftools filter for high-quality variants
    bcftools view -i 'QUAL>=30 && DP>=10 && AF>0.05' "${base}.vcf.gz" | \
        awk -F'\t' '{OFS="\t"; print $8}' > "${base}.af"

    # Extract allele frequency from INFO field
    grep -E 'AF=' "${base}.lofreq.vcf.gz" | cut -d'=' -f2- | tr -d ';' > "${base}.af.tmp"
    paste <(cut -f1,2,4,5,6,7 "${base}.vcf.gz") \
          <(cat "${base}.af.tmp") \
      | awk -F'\t' '{OFS="\t"; print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6}' > "${base}.tmp.tsv"

    # Append header if file is empty
    [ ! -s "${base}.tmp.tsv" ] && echo -e "sample\tchrom\tpos\tref\talt\taf" > "${base}.header.tmp"
    cat "${base}.header.tmp" "${base}.tmp.tsv" > "${base}.final.tsv"

    # Move final TSV to results/collapsed.tsv (append)
    if [ ! -s results/collapsed.tsv ]; then
        head -n 1 "${base}.final.tsv" > results/collapsed.tsv
    fi
    tail -n +2 "${base}.final.tsv" >> results/collapsed.tsv

    # Cleanup intermediate files
    rm -f "${base}."{bam,bai,lofreq.vcf.gz,vcf.gz,tbi,mpileup,af.tmp,tmp.tsv,header.tmp,final.tsv}
}

# Process each sample in parallel (max 4 jobs)
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
export -f process_sample
export results data/raw/chrM.fa

parallel -j 4 process_sample ::: "${samples[@]}"

# Ensure collapsed.tsv has header and proper format (idempotent)
[ ! -s results/collapsed.tsv ] && echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
sort -k1,1 -k2,2n results/collapsed.tsv | uniq > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv

exit 0