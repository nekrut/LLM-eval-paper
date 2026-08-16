#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

if [ ! -f data/ref/chrM.fa.amb ] || [ ! -f data/ref/chrM.fa.ann ] || \
   [ ! -f data/ref/chrM.fa.bwt ] || [ ! -f data/ref/chrM.fa.pac ] || \
   [ ! -f data/ref/chrM.fa.sa ]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in $SAMPLES; do
    bam_file="results/${sample}.bam"
    vcf_gz="results/${sample}.vcf.gz"
    
    # Skip if all outputs exist
    if [ -f "$bam_file" ] && [ -f "results/${sample}.bam.bai" ] && \
       [ -f "$vcf_gz" ] && [ -f "${vcf_gz}.tbi" ]; then
        continue
    fi
    
    # Alignment with bwa mem (using process substitution for gzipped FASTQs)
    bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        <(zcat "data/raw/${sample}_1.fq.gz") \
        <(zcat "data/raw/${sample}_2.fq.gz") | \
    samtools sort -@ $THREADS -o "$bam_file"
    
    # BAM indexing
    samtools index -@ $THREADS "$bam_file"
    
    # Variant calling with lofreq
    lofreq call-parallel --pp-threads $THREADS \
        -f data/ref/chrM.fa \
        -o "results/${sample}.vcf" \
        "$bam_file"
    
    # VCF compression and indexing
    bgzip -c "results/${sample}.vcf" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm "results/${sample}.vcf"
done

# Collapsed TSV generation (rebuild if any VCF is newer than existing TSV)
if [ ! -f results/collapsed.tsv ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done
else
    needs_rebuild=false
    for sample in $SAMPLES; do
        if [ "results/${sample}.vcf.gz" -nt "results/collapsed.tsv" ]; then
            needs_rebuild=true
            break
        fi
    done
    
    if $needs_rebuild; then
        echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
        for sample in $SAMPLES; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                "results/${sample}.vcf.gz" >> results/collapsed.tsv
        done
    fi
fi

exit 0